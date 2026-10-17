import Foundation
import Testing

@testable import Mewbell

private let alice = AccountID(host: "github.com", user: "alice")
private let bob = AccountID(host: "github.com", user: "bob")

private func thread(_ id: String, updatedAt: TimeInterval = 0) throws -> NotificationThread {
    NotificationThread(
        id: id, reason: "subscribed", updatedAt: Date(timeIntervalSince1970: updatedAt), title: "Thread \(id)",
        kind: .issue, subjectURL: nil, repository: try #require(RepositoryName(fullName: "octo/app")),
        detailsSubject: nil)
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

    /// alice の今のポーラーから `state` が届いたことにする。
    private func send(_ state: FeedState) async {
        await updates.byAccount[alice]?(state)
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

    @Test func ignoresAThreadThatCameBackUnchangedAfterLeavingTheList() async throws {
        let store = makeStore()
        await send(feed([try thread("1"), try thread("2")]))
        store.markRead(try thread("2"), in: alice)
        #expect(recorder.events.last == "threadsRemoved github.com/alice 2")
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

    @Test func removesTheThreadsOfAGroupMarkedDoneTogether() async throws {
        let store = makeStore()
        let threads = [try thread("1"), try thread("2"), try thread("3")]
        await send(feed(threads))
        recorder.events = []
        let group = RepositoryGroup(repository: threads[0].repository, threads: Array(threads.prefix(2)))
        store.markDone(group, in: alice)
        #expect(recorder.events == ["threadsRemoved github.com/alice 1,2"])
        store.stopAll()
    }

    @Test func removesAllThreadsMarkedDoneTogether() async throws {
        let store = makeStore()
        await send(feed([try thread("1"), try thread("2"), try thread("3")]))
        recorder.events = []
        store.markAllDone(in: alice)
        #expect(recorder.events == ["threadsRemoved github.com/alice 1,2,3"])
        store.stopAll()
    }

    /// すべて既読のように取り下げだけのときは、macOS の通知には渡すが `onNewThreads` は呼ばない。
    @Test func doesNotReportRetractionsAloneAsNewThreads() async throws {
        let store = makeStore()
        await send(feed([try thread("1"), try thread("2")]))
        await send(feed([]))
        #expect(recorder.changes[alice]?.map(\.retracted) == [["1", "2"]])
        #expect(received.value.isEmpty)
        store.stopAll()
    }

    @Test(arguments: [FeedPhase.unauthorized, .scopeInsufficient])
    func removesTheAccountWhenItStopsAndStartsOver(_ phase: FeedPhase) async throws {
        let store = makeStore()
        await send(feed([try thread("1")]))
        recorder.events = []
        await send(FeedState(phase: phase, threads: []))
        #expect(recorder.events == ["retractAll github.com/alice"])
        recorder.events = []
        // 再開の後の最初の取得は基準
        await send(feed([try thread("1"), try thread("2")]))
        #expect(recorder.events == ["baselineSet github.com/alice 1,2"])
        #expect(received.value.isEmpty)
        store.stopAll()
    }

    @Test func staysQuietForTheFirstFetchAfterStoppingAll() async throws {
        let store = makeStore()
        await send(feed([try thread("1")]))
        store.stopAll()
        // ポーラーを作り直す
        store.sync(
            with: .accounts([AccountStatus(account: Account(id: alice, isActive: true), tokenState: .ready)]))
        recorder.events = []
        await send(feed([try thread("1"), try thread("2")]))
        #expect(recorder.events == ["baselineSet github.com/alice 1,2"])
        #expect(received.value.isEmpty)
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

    @Test func postsTheEventAndDoesNotRepostWhenDetailsArrive() async throws {
        let notifier = SystemNotifier(center: center)
        let store = makeStore(notifier: notifier)
        await send(feed([try thread("1")]))
        var new = try thread("2")
        new.details = ThreadDetails(state: .open, event: ThreadEvent(kind: .commented, actor: "bob"))
        await send(feed([try thread("1"), new]))
        await notifier.waitForPendingWork()
        #expect(center.added.value.map(\.body) == ["Commented by bob · Watching · alice (github.com)"])
        // 知らせた後に取った状態とイベントを付け直しても、出し直さない
        var old = try thread("1")
        old.details = ThreadDetails(state: .closedCompleted, event: ThreadEvent(kind: .closed, actor: "carol"))
        await send(feed([old, new]))
        await notifier.waitForPendingWork()
        #expect(center.added.value.count == 1)
        #expect(store.feeds[alice]?.threads.first?.details == old.details)
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

}

/// `NotificationStore.sync` が、残すアカウントが決まったときだけ `onAccountsRetained` を呼ぶこと
/// （一覧の折りたたみの状態を、ポーラーと同じ判定で整理するため）。
@MainActor
struct NotificationStoreRetainedAccountsTests {
    private let transport = FakeHTTPTransport()
    private let tokens = FakeTokenProvider([alice: "test-token-alice", bob: "test-token-bob"])
    private let sleeper = ManualSleeper()
    /// `onAccountsRetained` に渡ったアカウント（呼ばれた順）
    private let retained = LockedValue<[Set<AccountID>]>([])

    private func makeStore() -> NotificationStore {
        let client = GitHubAPIClient(transport: transport)
        return NotificationStore(
            makePoller: { [tokens, sleeper] account, endpoints, _, _, _, _ in
                AccountPoller(
                    accountID: account.id, endpoints: endpoints, client: client, tokens: tokens,
                    sleep: sleeper.sleep, onUpdate: { _ in })
            }, openURL: { _ in },
            onAccountsRetained: { [retained] ids in retained.withLock { $0.append(ids) } })
    }

    @Test func reportsTheEnabledAccounts() {
        let store = makeStore()
        store.sync(
            with: .accounts([
                AccountStatus(account: Account(id: alice, isActive: true), tokenState: .ready),
                AccountStatus(account: Account(id: bob, isActive: false), tokenState: .disabled),
            ]))
        #expect(retained.value == [[alice]])
        store.stopAll()
    }

    @Test func reportsNothingWhileChecking() {
        let store = makeStore()
        store.sync(with: .checking)
        #expect(retained.value.isEmpty)
        store.stopAll()
    }

}
