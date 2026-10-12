import Foundation
import Testing

@testable import Mewbell

/// `AccountPoller.perform(.done)` に固有のテスト（既読と共通のものは `MarkReadPollingTests`）。
struct DonePollingTests {
    private let fixture: PollerFixture

    init() throws {
        fixture = try PollerFixture()
    }

    private func requests(_ method: String) -> [URLRequest] { fixture.requests(method) }
    private var lastIDs: [String] { fixture.lastIDs }

    @Test func keepsTheThreadOutOfAFetchThatEndsWhileTheDeleteIsInFlight() async {
        fixture.route(gets: [PollerFixture.ok(1...3), PollerFixture.ok(1...3), PollerFixture.ok(1...3)])
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
        fixture.route(gets: [PollerFixture.ok(1...3), PollerFixture.ok(1...3), PollerFixture.ok(1...3)])
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
        return PollerFixture.ok(body: Data("[\(body.joined(separator: ","))]".utf8), scopes: scopes)
    }

    /// 12:00 の `1` と 12:30 の `2`
    private static let twoThreads = ok([("1", noon), ("2", half)])
    /// 12:00 の `1`、12:30 の `2`、12:45 の `3`
    private static let threeThreads = ok([("1", noon), ("2", half), ("3", quarterTo)])

    private var puts: [URLRequest] { fixture.requests("PUT") }
    private var lastIDs: [String] { fixture.lastIDs }

    private static func lastReadAt(_ request: URLRequest) -> String? {
        guard let body = request.httpBody,
            let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else { return nil }
        return json["last_read_at"] as? String
    }

    /// `GET` には `gets` を順に返し、`PUT` には `put` の結果を返して、最初の取得まで進める。
    private func startLoaded(
        _ gets: [HTTPResponse], put: @escaping FakeHTTPTransport.Handler = { _ in HTTPResponse(statusCode: 202) }
    ) async {
        fixture.respond(gets: gets, other: put)
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
    }

    /// 最後に届いた一覧の最新のスレッドまで、すべて既読にする（store が表示中の一覧から決めるのと同じ）。
    private func markAllRead() async {
        await fixture.poller.markAllRead(through: fixture.last?.threads.map(\.updatedAt).max() ?? .distantPast)
    }

    @Test func leavesThreadsThatArrivedAfterTheClick() async throws {
        await startLoaded([Self.threeThreads])
        // 押したときに表示していた一覧の最新が 12:30 なら、その後に届いた 12:45 は既読にしない
        let half = try #require(ISO8601DateFormatter().date(from: Self.half))
        await fixture.poller.markAllRead(through: half)
        #expect(lastIDs == ["3"])
        #expect(puts.map(Self.lastReadAt) == [Self.half])
        fixture.poller.stop()
    }

    @Test func clearsTheListAndSendsThePut() async {
        await startLoaded([Self.twoThreads, PollerFixture.notModified])
        let updates = fixture.updates.value.count
        await markAllRead()
        #expect(lastIDs.isEmpty)
        #expect(fixture.updates.value.count > updates)
        #expect(puts.map { $0.url?.absoluteString } == ["https://api.github.com/notifications"])
        #expect(puts.first.flatMap(Self.lastReadAt) == Self.half)
        #expect(puts.first?.value(forHTTPHeaderField: "Authorization") == "Bearer test-token-alice")
        // 次の取得は条件なしで、取得の待ち時間は変わらない
        fixture.sleeper.advance()
        await fixture.sleeper.waitForSleeps(2)
        #expect(fixture.ifModifiedSince == [nil, nil])
        #expect(fixture.sleeper.durations == [.seconds(60), .seconds(60)])
        fixture.poller.stop()
    }

    @Test func keepsTheReadThreadsOutWhileGitHubFinishesTheAsyncRead() async {
        await startLoaded([Self.twoThreads, Self.threeThreads, Self.threeThreads])
        await markAllRead()
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

    @Test func keepsTheThreadsOutOfAFetchThatEndsWhileThePutIsInFlight() async {
        await startLoaded(
            [Self.twoThreads, Self.threeThreads, Self.twoThreads],
            put: { _ in HTTPResponse(statusCode: 500) })
        fixture.transport.pausedMethod.value = "PUT"
        let markAll = Task { await markAllRead() }
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

    @Test func aFailedLaterPutDoesNotEndAnEarlierOnesHiding() async {
        // 12:30 までの 1 回目は受け付けられ、12:45 までの 2 回目は失敗する
        await startLoaded(
            [Self.twoThreads, Self.threeThreads, Self.threeThreads],
            put: { request in
                HTTPResponse(statusCode: Self.lastReadAt(request) == Self.half ? 202 : 500)
            })
        await markAllRead()
        fixture.sleeper.advance()
        await fixture.sleeper.waitForSleeps(2)
        #expect(lastIDs == ["3"])
        await markAllRead()
        #expect(puts.map(Self.lastReadAt) == [Self.half, Self.quarterTo])
        // 2 回目の失敗の後も、1 回目の 202 の分（12:30 以前）は隠し続け、12:45 は戻る
        fixture.sleeper.advance()
        await fixture.sleeper.waitForSleeps(3)
        #expect(lastIDs == ["3"])
        fixture.poller.stop()
    }

    @Test func revealsTheThreadsWhenTheClockGoesBack() async {
        await startLoaded([Self.twoThreads, Self.twoThreads])
        await markAllRead()
        // 202 の後に時計が 1 時間戻ったら、期限の内とはみなさない
        fixture.advance(by: -3600)
        await fixture.sleeper.waitForSleeps(2)
        #expect(lastIDs == ["1", "2"])
        fixture.poller.stop()
    }

    @Test func sendsNothingWhileRetrying() async {
        // 2 回目の取得は通信の失敗になり、最後に取得できた 2 件を持ったまま待つ
        await startLoaded([Self.twoThreads])
        fixture.sleeper.advance()
        await fixture.sleeper.waitForSleeps(2)
        guard case .retrying = fixture.last?.phase else {
            Issue.record("Expected retrying, got \(String(describing: fixture.last?.phase))")
            return
        }
        await markAllRead()
        #expect(puts.isEmpty)
        #expect(lastIDs == ["1", "2"])
        fixture.poller.stop()
    }

    @Test func sendsNothingForAnEmptyList() async {
        await startLoaded([Self.ok([])])
        await markAllRead()
        #expect(puts.isEmpty)
        fixture.poller.stop()
    }

    @Test func neitherSendsNorClearsWithoutAToken() async {
        await startLoaded([Self.twoThreads])
        await fixture.tokens.discardToken(for: PollerFixture.alice)
        await markAllRead()
        #expect(puts.isEmpty)
        // 送れなかったことだけを知らせ、一覧はそのまま
        #expect(
            fixture.last?.actionFailure
                == ActionFailure(action: .markAllRead, kind: .noToken, occurredAt: fixture.clock.value))
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
        let first = Task { await markAllRead() }
        await waitUntil { self.puts.count == 1 }
        fixture.sleeper.advance()
        await fixture.sleeper.waitForSleeps(2)
        #expect(lastIDs == ["3"])
        let second = Task { await markAllRead() }
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
