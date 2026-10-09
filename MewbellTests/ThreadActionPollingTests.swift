import Foundation
import Testing

@testable import Mewbell

/// `AccountPoller.perform(.done)` のテスト。
struct DonePollingTests {
    private let fixture: PollerFixture

    init() throws {
        fixture = try PollerFixture()
    }

    /// `GET` には `gets` を順に返し（尽きたら通信の失敗）、`PATCH` には `205`、`DELETE` には `delete` を返す。
    private func route(gets: [HTTPResponse], delete: HTTPResponse = HTTPResponse(statusCode: 204)) {
        let queue = LockedValue(gets)
        fixture.transport.setHandler { request throws(TransportError) in
            switch request.httpMethod {
            case "PATCH": return HTTPResponse(statusCode: 205)
            case "DELETE": return delete
            default:
                guard let next = queue.withLock({ $0.isEmpty ? nil : $0.removeFirst() }) else {
                    throw .network(code: URLError.Code.notConnectedToInternet.rawValue)
                }
                return next
            }
        }
    }

    private func requests(_ method: String) -> [URLRequest] {
        fixture.transport.requests.filter { $0.httpMethod == method }
    }

    private var lastIDs: [String] { fixture.last?.threads.map(\.id) ?? [] }

    @Test func removesTheThreadAndSendsTheDelete() async {
        route(gets: [PollerFixture.ok(1...3), PollerFixture.notModified])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        await fixture.poller.perform(.done(threadID: "2"))
        #expect(lastIDs == ["1", "3"])
        #expect(
            requests("DELETE").map { $0.url?.absoluteString } == ["https://api.github.com/notifications/threads/2"])
        #expect(requests("DELETE").first?.value(forHTTPHeaderField: "Authorization") == "Bearer test-token-alice")
        #expect(requests("PATCH").isEmpty)
        fixture.sleeper.advance()
        await fixture.sleeper.waitForSleeps(2)
        #expect(requests("GET").map { $0.value(forHTTPHeaderField: "If-Modified-Since") } == [nil, nil])
        #expect(fixture.sleeper.durations == [.seconds(60), .seconds(60)])
        fixture.poller.stop()
    }

    @Test func bringsTheThreadBackWhenTheDeleteFailed() async {
        route(gets: [PollerFixture.ok(1...3), PollerFixture.ok(1...3)], delete: HTTPResponse(statusCode: 500))
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        await fixture.poller.perform(.done(threadID: "2"))
        #expect(lastIDs == ["1", "3"])
        fixture.sleeper.advance()
        await fixture.sleeper.waitForSleeps(2)
        #expect(lastIDs == ["1", "2", "3"])
        fixture.poller.stop()
    }

    @Test func keepsTheThreadOutOfAFetchThatEndsWhileTheDeleteIsInFlight() async {
        route(gets: [PollerFixture.ok(1...3), PollerFixture.ok(1...3), PollerFixture.ok(1...3)])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        fixture.transport.pausedMethod.value = "DELETE"
        let done = Task { await fixture.poller.perform(.done(threadID: "2")) }
        await waitUntil { self.requests("DELETE").count == 1 }
        #expect(lastIDs == ["1", "3"])
        // Done の応答を待っている間に終わった取得が 2 を返しても戻さない
        fixture.sleeper.advance()
        await fixture.sleeper.waitForSleeps(2)
        #expect(lastIDs == ["1", "3"])
        fixture.transport.pausedMethod.value = nil
        await done.value
        // Done の後に始めた取得の結果は、そのまま信じる
        fixture.sleeper.advance()
        await fixture.sleeper.waitForSleeps(3)
        #expect(lastIDs == ["1", "2", "3"])
        fixture.poller.stop()
    }

    @Test func keepsTheThreadHiddenUntilBothTheReadAndTheDoneEnd() async {
        route(gets: [PollerFixture.ok(1...3), PollerFixture.ok(1...3), PollerFixture.ok(1...3)])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        fixture.transport.pausedMethod.value = "PATCH"
        let read = Task { await fixture.poller.perform(.read(threadID: "2")) }
        await waitUntil { self.requests("PATCH").count == 1 }
        await fixture.poller.perform(.done(threadID: "2"))
        // Done は終わったが既読化が終わっていないので、Done の後に始めた取得でも戻さない
        fixture.sleeper.advance()
        await fixture.sleeper.waitForSleeps(2)
        #expect(lastIDs == ["1", "3"])
        fixture.transport.pausedMethod.value = nil
        await read.value
        fixture.sleeper.advance()
        await fixture.sleeper.waitForSleeps(3)
        #expect(lastIDs == ["1", "2", "3"])
        fixture.poller.stop()
    }

    @Test func sendsNothingWhileStopped() async {
        route(gets: [PollerFixture.ok(1...3, scopes: "gist")])
        fixture.poller.start()
        await waitUntil { self.fixture.last?.phase == .scopeInsufficient }
        await fixture.poller.perform(.done(threadID: "2"))
        #expect(requests("DELETE").isEmpty)
    }
}

/// `AccountPoller.markAllRead` のテスト。
struct MarkAllReadPollingTests {
    private let fixture: PollerFixture
    private static let noon = "2026-10-08T12:00:00Z"
    private static let half = "2026-10-08T12:30:00Z"
    private static let quarterTo = "2026-10-08T12:45:00Z"

    init() throws {
        fixture = try PollerFixture()
    }

    /// `updated_at` を指定したスレッドの `200`。
    private static func ok(_ threads: [(id: String, updatedAt: String)], scopes: String = "repo") -> HTTPResponse {
        let body = threads.map { FakeHTTPTransport.threadJSON(id: $0.id, updatedAt: $0.updatedAt) }
        return HTTPResponse(
            statusCode: 200, headers: ["Last-Modified": "LM-1", "X-OAuth-Scopes": scopes, "X-Poll-Interval": "60"],
            body: Data("[\(body.joined(separator: ","))]".utf8))
    }

    /// 12:00 の `1` と 12:30 の `2`
    private static let twoThreads = ok([("1", noon), ("2", half)])
    /// 12:00 の `1`、12:30 の `2`、12:45 の `3`
    private static let threeThreads = ok([("1", noon), ("2", half), ("3", quarterTo)])

    /// `GET` には `gets` を順に返し（尽きたら通信の失敗）、`PUT` には `put` の結果を返す。
    private func route(
        gets: [HTTPResponse],
        put: @escaping @Sendable (URLRequest) throws(TransportError) -> HTTPResponse = { _ in
            HTTPResponse(statusCode: 202)
        }
    ) {
        let queue = LockedValue(gets)
        fixture.transport.setHandler { request throws(TransportError) in
            if request.httpMethod == "PUT" {
                return try put(request)
            }
            guard let next = queue.withLock({ $0.isEmpty ? nil : $0.removeFirst() }) else {
                throw .network(code: URLError.Code.notConnectedToInternet.rawValue)
            }
            return next
        }
    }

    private var gets: [URLRequest] { fixture.transport.requests.filter { $0.httpMethod == "GET" } }
    private var puts: [URLRequest] { fixture.transport.requests.filter { $0.httpMethod == "PUT" } }
    private var lastIDs: [String] { fixture.last?.threads.map(\.id) ?? [] }

    private static func lastReadAt(_ request: URLRequest) -> String? {
        guard let body = request.httpBody,
            let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else { return nil }
        return json["last_read_at"] as? String
    }

    private func startLoaded(
        _ gets: [HTTPResponse], put: (@Sendable (URLRequest) throws(TransportError) -> HTTPResponse)? = nil
    )
        async
    {
        if let put {
            route(gets: gets, put: put)
        } else {
            route(gets: gets)
        }
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
    }

    @Test func clearsTheListAndSendsThePut() async {
        await startLoaded([Self.twoThreads, PollerFixture.notModified])
        let updates = fixture.updates.value.count
        await fixture.poller.markAllRead()
        #expect(lastIDs.isEmpty)
        #expect(fixture.updates.value.count > updates)
        #expect(puts.map { $0.url?.absoluteString } == ["https://api.github.com/notifications"])
        #expect(puts.first.flatMap(Self.lastReadAt) == Self.half)
        #expect(puts.first?.value(forHTTPHeaderField: "Authorization") == "Bearer test-token-alice")
        // 次の取得は条件なしで、取得の待ち時間は変わらない
        fixture.sleeper.advance()
        await fixture.sleeper.waitForSleeps(2)
        #expect(gets.map { $0.value(forHTTPHeaderField: "If-Modified-Since") } == [nil, nil])
        #expect(fixture.sleeper.durations == [.seconds(60), .seconds(60)])
        fixture.poller.stop()
    }

    @Test func keepsTheReadThreadsOutWhileGitHubFinishesTheAsyncRead() async {
        await startLoaded([Self.twoThreads, Self.threeThreads, Self.threeThreads])
        await fixture.poller.markAllRead()
        // 202 の 1 分後の取得: 12:30 以前は除き、12:45 は出す
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(2)
        #expect(lastIDs == ["3"])
        // 5 分を過ぎてから始めた取得の結果は、そのまま信じる
        fixture.advance(by: 300)
        await fixture.sleeper.waitForSleeps(3)
        #expect(lastIDs == ["1", "2", "3"])
        #expect(fixture.sleeper.durations == [.seconds(60), .seconds(60), .seconds(60)])
        fixture.poller.stop()
    }

    @Test func bringsTheThreadsBackWhenThePutFailed() async {
        await startLoaded(
            [Self.twoThreads, Self.twoThreads],
            put: { _ throws(TransportError) in throw .network(code: URLError.Code.timedOut.rawValue) })
        await fixture.poller.markAllRead()
        #expect(lastIDs.isEmpty)
        fixture.sleeper.advance()
        await fixture.sleeper.waitForSleeps(2)
        #expect(lastIDs == ["1", "2"])
        fixture.poller.stop()
    }

    @Test func keepsTheThreadsOutOfAFetchThatEndsWhileThePutIsInFlight() async {
        await startLoaded(
            [Self.twoThreads, Self.threeThreads, Self.twoThreads],
            put: { _ in HTTPResponse(statusCode: 500) })
        fixture.transport.pausedMethod.value = "PUT"
        let markAll = Task { await fixture.poller.markAllRead() }
        await waitUntil { self.puts.count == 1 }
        fixture.sleeper.advance()
        await fixture.sleeper.waitForSleeps(2)
        #expect(lastIDs == ["3"])
        fixture.transport.pausedMethod.value = nil
        await markAll.value
        // 失敗の後に始めた取得では戻る
        fixture.sleeper.advance()
        await fixture.sleeper.waitForSleeps(3)
        #expect(lastIDs == ["1", "2"])
        fixture.poller.stop()
    }

    @Test func sendsNothingForAnEmptyList() async {
        await startLoaded([Self.ok([])])
        await fixture.poller.markAllRead()
        #expect(puts.isEmpty)
        fixture.poller.stop()
    }

    @Test func sendsNothingWhileStopped() async {
        route(gets: [Self.ok([("1", Self.noon)], scopes: "gist")])
        fixture.poller.start()
        await waitUntil { self.fixture.last?.phase == .scopeInsufficient }
        await fixture.poller.markAllRead()
        #expect(puts.isEmpty)
    }

    @Test func neitherSendsNorClearsWithoutAToken() async {
        await startLoaded([Self.twoThreads])
        let updates = fixture.updates.value.count
        await fixture.tokens.discardToken(for: PollerFixture.alice)
        await fixture.poller.markAllRead()
        #expect(puts.isEmpty)
        #expect(fixture.updates.value.count == updates)
        #expect(lastIDs == ["1", "2"])
        fixture.poller.stop()
    }

    @Test func aFailedEarlierPutDoesNotEndALaterOnesHiding() async {
        // 12:30 までの 1 回目は失敗し、12:45 までの 2 回目は受け付けられる
        await startLoaded(
            [Self.twoThreads, Self.threeThreads, Self.threeThreads],
            put: { request in
                HTTPResponse(statusCode: Self.lastReadAt(request) == Self.half ? 500 : 202)
            })
        fixture.transport.pausedMethod.value = "PUT"
        let first = Task { await fixture.poller.markAllRead() }
        await waitUntil { self.puts.count == 1 }
        fixture.sleeper.advance()
        await fixture.sleeper.waitForSleeps(2)
        #expect(lastIDs == ["3"])
        let second = Task { await fixture.poller.markAllRead() }
        await waitUntil { self.puts.count == 2 }
        #expect(puts.map(Self.lastReadAt) == [Self.half, Self.quarterTo])
        fixture.transport.pausedMethod.value = nil
        await first.value
        await second.value
        fixture.sleeper.advance()
        await fixture.sleeper.waitForSleeps(3)
        #expect(lastIDs.isEmpty)
        fixture.poller.stop()
    }
}
