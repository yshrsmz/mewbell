import Foundation
import Testing

@testable import Mewbell

/// `If-Modified-Since` を付けた取得の `200` は、その時刻より後に更新されたスレッドだけなので、今の一覧に重ねる。
struct ConditionalFetchTests {
    private let fixture: PollerFixture

    init() throws {
        fixture = try PollerFixture()
    }

    /// `items` のスレッドの一覧（`updatedAt` は 2026-10-08 12:MM:00 で、`minute` が MM）。
    private static func list(_ items: [(id: Int, minute: Int)], lastModified: String) -> HTTPResponse {
        let json = items.map { item in
            FakeHTTPTransport.threadJSON(
                id: String(item.id), updatedAt: String(format: "2026-10-08T12:%02d:00Z", item.minute))
        }
        return PollerFixture.ok(body: Data("[\(json.joined(separator: ","))]".utf8), lastModified: lastModified)
    }

    private static let unconditional = list([(3, 2), (2, 1), (1, 0)], lastModified: "LM-1")

    @Test func mergesTheThreadsIntoTheCurrentList() async throws {
        fixture.respond([
            Self.unconditional, Self.list([(4, 6), (2, 5)], lastModified: "LM-2"), PollerFixture.notModified,
        ])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(2)
        #expect(fixture.ifModifiedSince == [nil, "LM-1"])
        #expect(fixture.lastIDs == ["4", "2", "3", "1"])
        let replaced = try #require(fixture.last?.threads.first { $0.id == "2" })
        #expect(replaced.updatedAt == ISO8601DateFormatter().date(from: "2026-10-08T12:05:00Z"))
        // 次の条件付きの取得には、重ねた 200 の `Last-Modified` を付ける
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(3)
        #expect(fixture.ifModifiedSince == [nil, "LM-1", "LM-2"])
        #expect(fixture.lastIDs == ["4", "2", "3", "1"])
        fixture.poller.stop()
    }

    /// 条件なしの 200 では、受け取らなかったスレッドを一覧から外す。
    @Test func replacesTheListWithAnUnconditional200() async {
        fixture.respond([Self.unconditional, Self.list([(4, 6)], lastModified: "LM-2")])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        fixture.moveClock(by: 20)
        await fixture.poller.refreshNow()
        #expect(fixture.ifModifiedSince == [nil, nil])
        #expect(fixture.lastIDs == ["4"])
        fixture.poller.stop()
    }

    /// 既読化のリクエストが終わっていない間の条件付きの 200 で、既読にしたスレッドを戻さない。
    @Test(arguments: [false, true])
    func keepsAThreadBeingReadOutOfTheMergedList(fetchedAgain: Bool) async {
        let fetched = fetchedAgain ? [(4, 6), (2, 5)] : [(4, 6)]
        fixture.route(gets: [Self.unconditional, Self.list(fetched, lastModified: "LM-2")])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        fixture.transport.pausedMethod.value = "PATCH"
        let read = Task { await fixture.poller.perform([.read(threadID: "2")]) }
        await waitUntil { fixture.requests("PATCH").count == 1 }
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(2)
        #expect(fixture.ifModifiedSince == [nil, "LM-1"])
        #expect(fixture.lastIDs == ["4", "3", "1"])
        fixture.transport.pausedMethod.value = nil
        await read.value
        fixture.poller.stop()
    }

    /// すべて既読のリクエストが終わっていない間の条件付きの 200 で、すべて既読の範囲のスレッドを戻さない。
    @Test func keepsThreadsMarkedAllReadOutOfTheMergedList() async throws {
        fixture.route(gets: [Self.unconditional, Self.list([(4, 6), (1, 0)], lastModified: "LM-2")])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        fixture.transport.pausedMethod.value = "PUT"
        let cutoff = try #require(ISO8601DateFormatter().date(from: "2026-10-08T12:02:00Z"))
        let markAllRead = Task { await fixture.poller.markAllRead(through: cutoff) }
        await waitUntil { fixture.requests("PUT").count == 1 }
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(2)
        #expect(fixture.ifModifiedSince == [nil, "LM-1"])
        #expect(fixture.lastIDs == ["4"])
        fixture.transport.pausedMethod.value = nil
        await markAllRead.value
        fixture.poller.stop()
    }
}

/// 条件付きの `200` で受け取らなかったスレッドの macOS の通知を、store が取り下げないこと。
@MainActor
struct NotificationStoreConditionalFetchTests {
    private let alice = PollerFixture.alice
    private let transport = FakeHTTPTransport()
    private let tokens = FakeTokenProvider([PollerFixture.alice: "test-token-alice"])
    private let sleeper = ManualSleeper()
    private let clock = LockedValue(PollerFixture.now)
    private let notifier = RecordingNotifier()

    private func makeStore(responses: [HTTPResponse]) -> NotificationStore {
        let queue = LockedValue(responses)
        transport.setHandler { _ throws(TransportError) in
            guard let next = queue.withLock({ $0.isEmpty ? nil : $0.removeFirst() }) else {
                throw .network(code: URLError.Code.notConnectedToInternet.rawValue)
            }
            return next
        }
        let client = GitHubAPIClient(transport: transport)
        return NotificationStore(
            makePoller: { [tokens, sleeper, clock] account, endpoints, _, _, _, onUpdate in
                AccountPoller(
                    accountID: account.id, endpoints: endpoints, client: client, tokens: tokens,
                    sleep: sleeper.sleep, now: { clock.value }, onUpdate: onUpdate)
            }, notifier: notifier, openURL: { _ in })
    }

    /// ポーラーが `sleeps` 回目の待ちに入ってから、時刻を進めて次の取得に進め、一覧が `count` 件になるまで待つ。
    private func advance(
        afterSleeps sleeps: Int, by seconds: TimeInterval, untilCount count: Int, in store: NotificationStore
    ) async {
        await sleeper.waitForSleeps(sleeps)
        clock.withLock { $0 = $0.addingTimeInterval(seconds) }
        sleeper.advance()
        await waitUntil { MainActor.assumeIsolated { store.feeds[alice]?.threads.count == count } }
    }

    @Test func retractsOnlyThreadsGoneFromAnUnconditional200() async {
        let store = makeStore(responses: [
            PollerFixture.ok(1...3), PollerFixture.ok(4...4, lastModified: "LM-2"),
            PollerFixture.ok(4...4, lastModified: "LM-3"),
        ])
        store.sync(with: .accounts([AccountStatus(account: Account(id: alice, isActive: true), tokenState: .ready)]))
        await waitUntil { MainActor.assumeIsolated { store.feeds[alice]?.threads.count == 3 } }

        await advance(afterSleeps: 1, by: 60, untilCount: 4, in: store)
        #expect(transport.ifModifiedSince == [nil, "LM-1"])
        #expect(notifier.changes[alice]?.map(\.posted) == [["4"]])
        #expect(notifier.changes[alice]?.map(\.retracted) == [[]])

        // 最初の取得から 5 分たったので条件なしで取り直し、受け取らなかったスレッドを取り下げる
        await advance(afterSleeps: 2, by: 240, untilCount: 1, in: store)
        #expect(transport.ifModifiedSince == [nil, "LM-1", nil])
        #expect(notifier.changes[alice]?.last?.retracted == ["1", "2", "3"])
        store.stopAll()
    }
}
