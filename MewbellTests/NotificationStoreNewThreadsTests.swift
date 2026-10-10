import Foundation
import Testing

@testable import Mewbell

private let alice = AccountID(host: "github.com", user: "alice")
private let bob = AccountID(host: "github.com", user: "bob")

private func thread(_ id: String, updatedAt: TimeInterval = 0) throws -> NotificationThread {
    NotificationThread(
        id: id, reason: "subscribed", updatedAt: Date(timeIntervalSince1970: updatedAt), title: "Thread \(id)",
        kind: .issue, subjectURL: nil, repository: try #require(RepositoryName(fullName: "octo/app")))
}

/// ポーラーの `onUpdate` を受け取っておく（ポーラー自身の更新は捨て、テストが流す `FeedState` だけを届ける）。
@MainActor
private final class FeedUpdates {
    var byAccount: [AccountID: @Sendable (FeedState) async -> Void] = [:]
}

/// `NotificationStore` の新着の判定（`NotificationTracker`）と、それを `ThreadNotifying` と `onNewThreads` に配ること。
@MainActor
struct NotificationStoreNewThreadsTests {
    private let transport = FakeHTTPTransport()
    private let tokens = FakeTokenProvider([alice: "test-token-alice", bob: "test-token-bob"])
    private let sleeper = ManualSleeper()
    private let updates = FeedUpdates()
    private let recorder = RecordingNotifier()
    private let center = FakeUserNotificationCenter()
    /// `onNewThreads` に渡ったスレッドの ID（届いた順）
    private let received = LockedValue<[[String]]>([])
    private let loaded = FeedPhase.loaded(updatedAt: Date(timeIntervalSince1970: 0))

    private func feed(_ threads: [NotificationThread]) -> FeedState {
        FeedState(phase: loaded, threads: threads)
    }

    /// alice と bob のポーラーを作った store。`onNewThreads` は alice の分だけを `received` に集める。
    private func makeStore(notifier: (any ThreadNotifying)? = nil) -> NotificationStore {
        let client = GitHubAPIClient(transport: transport)
        let store = NotificationStore(
            makePoller: { [updates, tokens, sleeper] account, endpoints, _, _, _, onUpdate in
                updates.byAccount[account.id] = onUpdate
                return AccountPoller(
                    accountID: account.id, endpoints: endpoints, client: client, tokens: tokens,
                    sleep: sleeper.sleep, onUpdate: { _ in })
            }, notifier: notifier ?? recorder, openURL: { _ in },
            onNewThreads: { [received] account, threads in
                if account == alice {
                    received.withLock { $0.append(threads.map(\.id)) }
                }
            })
        store.sync(
            with: .accounts([
                AccountStatus(account: Account(id: alice, isActive: true), tokenState: .ready),
                AccountStatus(account: Account(id: bob, isActive: false), tokenState: .ready),
            ]))
        recorder.events = []
        return store
    }

    /// 今のポーラーから `state` が届いたことにする。
    private func send(_ state: FeedState, for account: AccountID = alice) async {
        await updates.byAccount[account]?(state)
    }

    @Test func staysQuietForTheBaseline() async throws {
        let store = makeStore()
        await send(feed([try thread("1"), try thread("2")]))
        #expect(recorder.events == ["baselineSet github.com/alice 1,2"])
        #expect(received.value.isEmpty)
        store.stopAll()
    }

    @Test func reportsNewThreadsAndGoneOnes() async throws {
        let store = makeStore()
        await send(feed([try thread("1"), try thread("2")]))
        let second = feed([try thread("2"), try thread("3")])
        await send(second)
        #expect(recorder.changes[alice]?.map(\.posted) == [["3"]])
        #expect(recorder.changes[alice]?.map(\.retracted) == [["1"]])
        #expect(received.value == [["3"]])
        // 304 の後（スレッドが同じ）は何もしない
        await send(FeedState(phase: .loaded(updatedAt: .now), threads: second.threads))
        #expect(recorder.changes[alice]?.count == 1)
        #expect(received.value.count == 1)
        store.stopAll()
    }

    @Test func reportsNewAndUpdatedThreads() async throws {
        let store = makeStore()
        await send(feed([try thread("1"), try thread("2")]))
        await send(feed([try thread("1"), try thread("2", updatedAt: 60), try thread("3")]))
        #expect(received.value == [["2", "3"]])
        #expect(recorder.changes[alice]?.map(\.posted) == [["2", "3"]])
        store.stopAll()
    }

    @Test func ignoresChangesOfOnlyTheDiagnostics() async throws {
        let store = makeStore()
        let first = feed([try thread("1")])
        await send(first)
        var second = first
        second.isTruncated = true
        second.actionFailure = ActionFailure(action: .done, kind: .httpStatus(500), occurredAt: .now)
        second.diagnostics.nextFetchAt = .now
        await send(second)
        #expect(recorder.events == ["baselineSet github.com/alice 1"])
        #expect(received.value.isEmpty)
        store.stopAll()
    }

    @Test func makesTheBaselineAfterAFailedFirstFetch() async throws {
        let store = makeStore()
        await send(FeedState(phase: .retrying(nextAttempt: .now, rateLimited: false), threads: []))
        #expect(recorder.events.isEmpty)
        await send(feed([]))
        #expect(recorder.events == ["baselineSet github.com/alice "])
        await send(feed([try thread("1")]))
        #expect(recorder.changes[alice]?.map(\.posted) == [["1"]])
        #expect(received.value == [["1"]])
        store.stopAll()
    }

    @Test func doesNotReportARemovedThreadThatComesBackUnchanged() async throws {
        let store = makeStore()
        let first = feed([try thread("1"), try thread("2")])
        await send(first)
        store.markRead(try thread("2"), in: alice)
        #expect(recorder.events.last == "threadRemoved github.com/alice 2")
        // 次の取得で、同じ updated_at のまま一覧に戻っても知らせない
        await send(first)
        #expect(recorder.changes[alice] == nil)
        #expect(received.value.isEmpty)
        store.stopAll()
    }

    @Test func ignoresAThreadThatCameBackUnchangedAfterLeavingTheList() async throws {
        let store = makeStore()
        await send(feed([try thread("1"), try thread("2")]))
        store.markRead(try thread("2"), in: alice)
        // 既読にしたスレッドは取り下げ済みなので、次の取得で一覧に無くても取り下げ直さない
        await send(feed([try thread("1"), try thread("3")]))
        #expect(recorder.changes[alice]?.map(\.posted) == [["3"]])
        #expect(recorder.changes[alice]?.map(\.retracted) == [[]])
        // 同じ updated_at のまま一覧に戻っても知らせない
        await send(feed([try thread("1"), try thread("2"), try thread("3")]))
        #expect(recorder.changes[alice]?.count == 1)
        #expect(received.value == [["3"]])
        store.stopAll()
    }

    @Test func reportsOnlyTheAccountMarkedAllRead() async throws {
        let store = makeStore()
        let aliceThreads = feed([try thread("1"), try thread("2")])
        await send(aliceThreads)
        await send(feed([try thread("3")]), for: bob)
        await send(feed([]))
        #expect(recorder.changes[alice]?.map(\.posted) == [[]])
        #expect(recorder.changes[alice]?.map(\.retracted) == [["1", "2"]])
        #expect(recorder.changes[bob] == nil)
        store.stopAll()
    }

    @Test func doesNothingWhileRetrying() async throws {
        let store = makeStore()
        let first = feed([try thread("1")])
        await send(first)
        recorder.events = []
        await send(FeedState(phase: .retrying(nextAttempt: .now, rateLimited: false), threads: first.threads))
        #expect(recorder.events.isEmpty)
        #expect(received.value.isEmpty)
        store.stopAll()
    }

    @Test(arguments: [FeedPhase.unauthorized, .scopeInsufficient])
    func removesTheAccountWhenItStops(_ phase: FeedPhase) async throws {
        let store = makeStore()
        await send(feed([try thread("1")]))
        recorder.events = []
        await send(FeedState(phase: phase, threads: []))
        #expect(recorder.events == ["accountRemoved github.com/alice"])
        store.stopAll()
    }

    @Test(arguments: [FeedPhase.unauthorized, .scopeInsufficient])
    func startsOverAfterStopping(_ phase: FeedPhase) async throws {
        let store = makeStore()
        await send(feed([try thread("1")]))
        await send(FeedState(phase: phase, threads: []))
        recorder.events = []
        // 再開の後の最初の取得は基準
        await send(feed([try thread("1"), try thread("2")]))
        #expect(recorder.events == ["baselineSet github.com/alice 1,2"])
        #expect(received.value.isEmpty)
        store.stopAll()
    }

    @Test func staysQuietForTheFirstFetchAfterARestart() async throws {
        let store = makeStore()
        await send(feed([try thread("1")]))
        store.restart(alice)
        await send(feed([try thread("1"), try thread("5")]))
        #expect(received.value.isEmpty)
        #expect(recorder.events == ["baselineSet github.com/alice 1", "baselineSet github.com/alice 1,5"])
        store.stopAll()
    }

    @Test func treatsTheFirstFetchAfterARestartAsTheBaseline() async throws {
        let notifier = SystemNotifier(center: center)
        let store = makeStore(notifier: notifier)
        await send(feed([try thread("1"), try thread("2")]))
        await notifier.waitForPendingWork()
        center.delivered.value = ["github.com/alice/1", "github.com/alice/2"]
        store.restart(alice)
        await notifier.waitForPendingWork()
        // 取り直しの間は通知を残し、基準の取り直しで今の一覧に無いものだけを消す
        #expect(center.delivered.value.count == 2)
        await send(feed([try thread("2"), try thread("4")]))
        await notifier.waitForPendingWork()
        #expect(center.added.value.isEmpty)
        #expect(center.delivered.value == ["github.com/alice/2"])
        store.stopAll()
    }

    @Test func reportsEvenWhenNotificationsAreOff() async throws {
        let notifier = SystemNotifier(center: center, notifies: { _ in false })
        let store = makeStore(notifier: notifier)
        await send(feed([try thread("1")]))
        await send(feed([try thread("1"), try thread("2")]))
        await notifier.waitForPendingWork()
        #expect(received.value == [["2"]])
        #expect(center.added.value.isEmpty)
        store.stopAll()
    }

    @Test func doesNotPostWhatArrivedWhileOffWhenTurnedBackOn() async throws {
        let enabled = LockedValue(false)
        let notifier = SystemNotifier(center: center, notifies: { _ in enabled.value })
        let store = makeStore(notifier: notifier)
        await send(feed([try thread("1")]))
        let whileOff = feed((1...6).compactMap { try? thread(String($0)) })
        await send(whileOff)
        enabled.value = true
        await send(feed(whileOff.threads + [try thread("789")]))
        await notifier.waitForPendingWork()
        #expect(center.added.value.map(\.identifier) == ["github.com/alice/789"])
        #expect(received.value == [["2", "3", "4", "5", "6"], ["789"]])
        store.stopAll()
    }
}
