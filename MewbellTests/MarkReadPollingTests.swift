import Foundation
import Testing

@testable import Mewbell

/// `AccountPoller.perform(.read)` のテスト。
struct MarkReadPollingTests {
    private let fixture: PollerFixture

    init() throws {
        fixture = try PollerFixture()
    }

    /// `GET` には `gets` を順に返し（尽きたら通信の失敗）、`PATCH` には `patch` を返す。
    private func route(gets: [HTTPResponse], patch: HTTPResponse = HTTPResponse(statusCode: 205)) {
        let queue = LockedValue(gets)
        fixture.transport.setHandler { request throws(TransportError) in
            if request.httpMethod == "PATCH" {
                return patch
            }
            guard let next = queue.withLock({ $0.isEmpty ? nil : $0.removeFirst() }) else {
                throw .network(code: URLError.Code.notConnectedToInternet.rawValue)
            }
            return next
        }
    }

    private var gets: [URLRequest] { fixture.transport.requests.filter { $0.httpMethod == "GET" } }
    private var patches: [URLRequest] { fixture.transport.requests.filter { $0.httpMethod == "PATCH" } }
    private var lastIDs: [String] { fixture.last?.threads.map(\.id) ?? [] }

    @Test func removesTheThreadAndSendsThePatch() async {
        route(gets: [PollerFixture.ok(1...3), PollerFixture.notModified])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        await fixture.poller.perform(.read(threadID: "2"))
        #expect(lastIDs == ["1", "3"])
        #expect(patches.map { $0.url?.absoluteString } == ["https://api.github.com/notifications/threads/2"])
        #expect(patches.first?.value(forHTTPHeaderField: "Authorization") == "Bearer test-token-alice")
        // 次の取得は条件なしで、取得は早まらない
        #expect(fixture.sleeper.durations == [.seconds(60)])
        fixture.sleeper.advance()
        await fixture.sleeper.waitForSleeps(2)
        #expect(gets.map { $0.value(forHTTPHeaderField: "If-Modified-Since") } == [nil, nil])
        #expect(fixture.sleeper.durations == [.seconds(60), .seconds(60)])
        fixture.poller.stop()
    }

    @Test func bringsTheThreadBackWhenThePatchFailed() async {
        route(gets: [PollerFixture.ok(1...3), PollerFixture.ok(1...3)], patch: HTTPResponse(statusCode: 500))
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        await fixture.poller.perform(.read(threadID: "2"))
        #expect(lastIDs == ["1", "3"])
        fixture.sleeper.advance()
        await fixture.sleeper.waitForSleeps(2)
        #expect(lastIDs == ["1", "2", "3"])
        fixture.poller.stop()
    }

    @Test func keepsTheThreadOutOfAFetchStartedBeforeMarkingItRead() async {
        route(gets: [PollerFixture.ok(1...3), PollerFixture.ok(1...3), PollerFixture.ok(1...1)])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        // 2 回目の取得の応答を止めている間に既読にする
        fixture.transport.pausedMethod.value = "GET"
        fixture.sleeper.advance()
        await waitUntil { self.gets.count == 2 }
        await fixture.poller.perform(.read(threadID: "2"))
        #expect(patches.count == 1)
        fixture.transport.pausedMethod.value = nil
        await fixture.sleeper.waitForSleeps(2)
        #expect(lastIDs == ["1", "3"])
        // 既読化の後に始めた取得の結果は、そのまま信じる
        fixture.sleeper.advance()
        await fixture.sleeper.waitForSleeps(3)
        #expect(lastIDs == ["1"])
        #expect(gets.last?.value(forHTTPHeaderField: "If-Modified-Since") == nil)
        fixture.poller.stop()
    }

    @Test func sendsNothingWhileStopped() async {
        route(gets: [PollerFixture.ok(1...3, scopes: "gist")])
        fixture.poller.start()
        await waitUntil { self.fixture.last?.phase == .scopeInsufficient }
        await fixture.poller.perform(.read(threadID: "2"))
        #expect(patches.isEmpty)
    }
}
