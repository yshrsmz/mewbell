import Foundation
import Observation
import Testing

@testable import Mewbell

private let alice = AccountID(host: "github.com", user: "alice")
private let bob = AccountID(host: "github.com", user: "bob")

private func thread(_ id: String, _ repository: String, updatedAt: TimeInterval) throws -> NotificationThread {
    NotificationThread(
        id: id, reason: "subscribed", updatedAt: Date(timeIntervalSince1970: updatedAt), title: "Thread \(id)",
        kind: .issue, subjectURL: nil, repository: try #require(RepositoryName(fullName: repository)),
        subjectNumber: nil)
}

/// ポーラーの `onUpdate` を受け取っておく（ポーラー自身の更新は捨て、テストが流す `FeedState` だけを届ける）。
@MainActor
private final class FeedUpdates {
    var byAccount: [AccountID: @Sendable (FeedState) async -> Void] = [:]
}

/// `NotificationStore` がアカウントごとのリポジトリのグループを、スレッドが変わったときだけ作ること。
@MainActor
struct NotificationStoreRepositoriesTests {
    private let transport = FakeHTTPTransport()
    private let tokens = FakeTokenProvider([alice: "test-token-alice", bob: "test-token-bob"])
    private let sleeper = ManualSleeper()
    private let updates = FeedUpdates()
    private let loaded = FeedPhase.loaded(updatedAt: Date(timeIntervalSince1970: 0))

    private func statuses(aliceState: TokenState = .ready) -> DiscoveryState {
        .accounts([
            AccountStatus(account: Account(id: alice, isActive: true), tokenState: aliceState),
            AccountStatus(account: Account(id: bob, isActive: false), tokenState: .ready),
        ])
    }

    /// alice と bob のポーラーを作った store。
    private func makeStore() -> NotificationStore {
        let client = GitHubAPIClient(transport: transport)
        let store = NotificationStore(
            makePoller: { [updates, tokens, sleeper] account, endpoints, _, _, _, onUpdate in
                updates.byAccount[account.id] = onUpdate
                return AccountPoller(
                    accountID: account.id, endpoints: endpoints, client: client, tokens: tokens,
                    sleep: sleeper.sleep, onUpdate: { _ in })
            }, openURL: { _ in })
        store.sync(with: statuses())
        return store
    }

    /// 今のポーラーから `state` が届いたことにする。
    private func send(_ state: FeedState, for account: AccountID = alice) async {
        await updates.byAccount[account]?(state)
    }

    private func threads() throws -> [NotificationThread] {
        [
            try thread("1", "octo/app", updatedAt: 100),
            try thread("2", "octo/lib", updatedAt: 300),
            try thread("3", "octo/app", updatedAt: 200),
        ]
    }

    @Test func groupsTheThreadsOfAnArrivedFeed() async throws {
        let store = makeStore()
        await send(FeedState(phase: loaded, threads: try threads()))
        let groups = try #require(store.repositories[alice])
        #expect(groups == RepositoryGroup.groups(from: try threads()))
        #expect(groups.map(\.id) == ["octo/lib", "octo/app"])
        #expect(groups[1].threads.map(\.id) == ["3", "1"])
        store.stopAll()
    }

    @Test func keepsTheGroupsWhenOnlyTheDiagnosticsChange() async throws {
        let store = makeStore()
        let first = FeedState(phase: loaded, threads: try threads())
        await send(first)
        let changed = LockedValue(false)
        withObservationTracking {
            _ = store.repositories
        } onChange: {
            changed.withLock { $0 = true }
        }
        var second = first
        second.phase = .loaded(updatedAt: .now)
        second.isTruncated = true
        second.diagnostics.nextFetchAt = .now
        await send(second)
        #expect(store.feeds[alice] == second)
        #expect(!changed.value)
        store.stopAll()
    }

    @Test func dropsAThreadMarkedReadFromItsGroup() async throws {
        let store = makeStore()
        await send(FeedState(phase: loaded, threads: try threads()))
        store.markRead(try thread("1", "octo/app", updatedAt: 100), in: alice)
        #expect(store.repositories[alice]?.map(\.id) == ["octo/lib", "octo/app"])
        #expect(store.repositories[alice]?[1].threads.map(\.id) == ["3"])
        // 最後の 1 件ならグループごと消える
        store.markRead(try thread("2", "octo/lib", updatedAt: 300), in: alice)
        #expect(store.repositories[alice]?.map(\.id) == ["octo/app"])
        store.stopAll()
    }

    @Test func forgetsTheGroupsOfADisabledAccount() async throws {
        let store = makeStore()
        await send(FeedState(phase: loaded, threads: try threads()))
        await send(FeedState(phase: loaded, threads: [try thread("4", "acme/web", updatedAt: 50)]), for: bob)
        #expect(store.repositories[alice]?.isEmpty == false)
        store.sync(with: statuses(aliceState: .disabled))
        #expect(store.feeds[alice] == nil)
        #expect(store.repositories[alice] == nil)
        #expect(store.repositories[bob]?.map(\.id) == ["acme/web"])
        store.stopAll()
    }
}
