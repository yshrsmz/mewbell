import Foundation
import Testing

@testable import Mewbell

/// `AccountPoller.perform` のテスト。既読と Done で同じ振る舞いは、両方で確かめる。
struct MarkReadPollingTests {
    private let fixture: PollerFixture

    init() throws {
        fixture = try PollerFixture()
    }

    private var gets: [URLRequest] { fixture.requests("GET") }
    private var patches: [URLRequest] { fixture.requests("PATCH") }
    private var lastIDs: [String] { fixture.lastIDs }

    private static let actions = [ThreadAction.read(threadID: "2"), .done(threadID: "2")]

    @Test(arguments: actions)
    func removesTheThreadAndSendsTheRequest(_ action: ThreadAction) async {
        fixture.route(gets: [PollerFixture.ok(1...3), PollerFixture.ok(1...3), PollerFixture.notModified])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        await fixture.poller.perform(action)
        #expect(lastIDs == ["1", "3"])
        let method = if case .read = action { "PATCH" } else { "DELETE" }
        let sent = fixture.transport.requests.filter { $0.httpMethod != "GET" }
        #expect(
            sent.map { "\($0.httpMethod ?? "") \($0.url?.absoluteString ?? "")" }
                == ["\(method) https://api.github.com/notifications/threads/2"])
        // 次の取得は条件なしで、取得は早まらない
        #expect(fixture.sleeper.durations == [.seconds(60)])
        fixture.sleeper.advance()
        await fixture.sleeper.waitForSleeps(2)
        // 取り終えたら、その次はまた条件付きに戻る
        fixture.sleeper.advance()
        await fixture.sleeper.waitForSleeps(3)
        #expect(gets.map { $0.value(forHTTPHeaderField: "If-Modified-Since") } == [nil, nil, "LM-1"])
        #expect(fixture.sleeper.durations == [60, 60, 60].map { .seconds($0) })
        fixture.poller.stop()
    }

    @Test(arguments: actions)
    func bringsTheThreadBackWhenTheRequestFailed(_ action: ThreadAction) async {
        fixture.route(gets: [PollerFixture.ok(1...3), PollerFixture.ok(1...3)], [:])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        await fixture.poller.perform(action)
        #expect(lastIDs == ["1", "3"])
        fixture.sleeper.advance()
        await fixture.sleeper.waitForSleeps(2)
        #expect(lastIDs == ["1", "2", "3"])
        fixture.poller.stop()
    }

    @Test func keepsTheThreadOutOfAFetchStartedBeforeMarkingItRead() async {
        fixture.route(gets: [PollerFixture.ok(1...3), PollerFixture.ok(1...3), PollerFixture.ok(1...1)])
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
}
