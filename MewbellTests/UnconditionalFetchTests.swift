import Foundation
import Testing

@testable import Mewbell

/// `Last-Modified` より古いスレッドの増減を `304` が隠すので、定期的と再読み込みの後に条件なしで取り直す。
struct UnconditionalFetchTests {
    private let fixture: PollerFixture

    init() throws {
        fixture = try PollerFixture()
    }

    @Test func refetchesWithoutIfModifiedSinceEveryFiveMinutes() async {
        fixture.respond([
            PollerFixture.ok(1...3), PollerFixture.notModified, PollerFixture.ok(1...2, lastModified: "LM-2"),
            PollerFixture.notModified,
        ])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(2)
        #expect(fixture.ifModifiedSince == [nil, "LM-1"])
        #expect(fixture.last?.threads.count == 3)

        // 最初の取得から 5 分
        fixture.advance(by: 240)
        await fixture.sleeper.waitForSleeps(3)
        #expect(fixture.ifModifiedSince == [nil, "LM-1", nil])
        #expect(fixture.last?.threads.map(\.id) == ["1", "2"])

        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(4)
        #expect(fixture.ifModifiedSince == [nil, "LM-1", nil, "LM-2"])
        fixture.poller.stop()
    }

    /// 条件なしにした取得（5 分たった、または再読み込み）が失敗したら、次の取得もまた条件なしにする。
    @Test(arguments: [false, true])
    func retriesWithoutIfModifiedSinceAfterAFailedUnconditionalFetch(requested: Bool) async {
        fixture.respond([PollerFixture.ok(1...1), HTTPResponse(statusCode: 500), PollerFixture.notModified])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        if requested {
            fixture.poller.requestUnconditionalFetch()
        }
        fixture.advance(by: requested ? 60 : 300)
        await fixture.sleeper.waitForSleeps(2)
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(3)
        #expect(fixture.ifModifiedSince == [nil, nil, nil])
        fixture.poller.stop()
    }

    @Test func requestedFetchIsUnconditionalButNotEarlier() async {
        fixture.respond([
            PollerFixture.ok(1...1), PollerFixture.ok(1...2, lastModified: "LM-2"), PollerFixture.notModified,
        ])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        fixture.poller.requestUnconditionalFetch()
        try? await Task.sleep(for: .milliseconds(50))
        // 取得は早まらない
        #expect(fixture.transport.requests.count == 1)

        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(2)
        #expect(fixture.ifModifiedSince == [nil, nil])
        #expect(fixture.last?.threads.count == 2)

        // 取り終えたら、その次はまた条件付きに戻る
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(3)
        #expect(fixture.ifModifiedSince == [nil, nil, "LM-2"])
        #expect(fixture.sleeper.durations == [60, 60, 60].map { .seconds($0) })
        fixture.poller.stop()
    }

    @MainActor
    @Test func storePassesTheRequestToItsPollers() async throws {
        let alice = PollerFixture.alice
        let transport = FakeHTTPTransport { _ in PollerFixture.ok(1...1) }
        let tokens = FakeTokenProvider([alice: "test-token-alice"])
        let sleeper = ManualSleeper()
        let client = GitHubAPIClient(transport: transport)
        let store = NotificationStore { account, endpoints, onUpdate in
            AccountPoller(
                accountID: account.id, endpoints: endpoints, client: client, tokens: tokens, sleep: sleeper.sleep,
                onUpdate: onUpdate)
        }
        store.sync(
            with: .accounts([AccountStatus(account: Account(id: alice, isActive: true), tokenState: .ready)]))
        await sleeper.waitForSleeps(1)
        store.requestUnconditionalFetch()
        sleeper.advance()
        await sleeper.waitForSleeps(2)
        let sent = transport.requests.map { $0.value(forHTTPHeaderField: "If-Modified-Since") }
        #expect(sent == [nil, nil])
        store.stopAll()
    }
}
