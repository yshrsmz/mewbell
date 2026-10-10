import Foundation
import Testing

@testable import Mewbell

/// `participating` を付けた取得。
struct ParticipatingPollerTests {
    private let transport = FakeHTTPTransport()
    private let sleeper = ManualSleeper()

    private func poller(host: String, participating: Bool) throws -> AccountPoller {
        let id = AccountID(host: host, user: "dave")
        return AccountPoller(
            accountID: id, endpoints: try #require(APIEndpoints(host: host)),
            client: GitHubAPIClient(transport: transport), tokens: FakeTokenProvider([id: "test-token-dave"]),
            participating: participating, sleep: sleeper.sleep, onUpdate: { _ in })
    }

    @Test func sendsParticipatingTrue() async throws {
        let poller = try poller(host: "acme.ghe.com", participating: true)
        poller.start()
        await waitUntil { !self.transport.requests.isEmpty }
        poller.stop()
        #expect(
            transport.requests.first?.url?.absoluteString
                == "https://api.acme.ghe.com/notifications?all=false&participating=true&per_page=50")
    }

    @Test func sendsParticipatingFalseByDefault() async throws {
        let poller = try poller(host: "github.com", participating: false)
        poller.start()
        await waitUntil { !self.transport.requests.isEmpty }
        poller.stop()
        #expect(
            transport.requests.first?.url?.absoluteString
                == "https://api.github.com/notifications?all=false&participating=false&per_page=50")
    }

    @Test func followsTheNextLinkAsIs() async throws {
        let next = "https://api.acme.ghe.com/notifications?all=false&participating=true&per_page=50&page=2"
        transport.setHandler { request in
            if request.url?.absoluteString == next {
                return HTTPResponse(
                    statusCode: 200, headers: ["X-OAuth-Scopes": "repo"], body: FakeHTTPTransport.page(3...3))
            }
            return HTTPResponse(
                statusCode: 200, headers: ["X-OAuth-Scopes": "repo", "Link": "<\(next)>; rel=\"next\""],
                body: FakeHTTPTransport.page(1...2))
        }
        let poller = try poller(host: "acme.ghe.com", participating: true)
        poller.start()
        await waitUntil { self.transport.requests.count >= 2 }
        poller.stop()
        #expect(transport.requests.map { $0.url?.absoluteString }.last == next)
    }
}

/// `ThreadNotifying` への呼び出しを記録する。
@MainActor
final class RecordingNotifier: ThreadNotifying {
    var events: [String] = []
    /// `feedChanged` で届いたスレッドの ID（アカウントごと、届いた順）
    var feeds: [AccountID: [[String]]] = [:]

    func feedChanged(for account: AccountID, from old: FeedState?, to new: FeedState) {
        if case .loaded = new.phase {
            feeds[account, default: []].append(new.threads.map(\.id))
        }
    }

    func threadRemoved(_ threadID: String, for account: AccountID) {
        events.append("threadRemoved \(account) \(threadID)")
    }

    func accountRemoved(_ account: AccountID) {
        events.append("accountRemoved \(account)")
    }

    func resetBaseline(_ account: AccountID) {
        events.append("resetBaseline \(account)")
    }

    func notificationsDisabled(_ account: AccountID) {
        events.append("notificationsDisabled \(account)")
    }

    func retainOnly(_ accounts: Set<AccountID>) {
        events.append("retainOnly \(accounts.map(\.description).sorted().joined(separator: ","))")
    }
}

/// 無効なアカウントと `participating` の切り替えでの `NotificationStore`。
@MainActor
struct NotificationStoreSettingsTests {
    private let alice = AccountID(host: "github.com", user: "alice")
    private let bob = AccountID(host: "github.com", user: "bob")
    /// `participating=true` には 4〜5、`false` には 1〜3 を返す
    private let transport = FakeHTTPTransport { request in
        let participating = request.url?.query?.contains("participating=true") == true
        return PollerFixture.ok(participating ? 4...5 : 1...3)
    }
    private let tokens = FakeTokenProvider()
    private let sleeper = ManualSleeper()
    private let notifier = RecordingNotifier()
    private let settings = AppSettings(storage: InMemorySettingsStorage())
    /// ポーラーを作ったときの (アカウント, participating)
    private let made = LockedValue<[String]>([])
    private let opened = LockedValue<[URL]>([])

    private func makeStore() -> NotificationStore {
        tokens.set("test-token-alice", for: alice)
        tokens.set("test-token-bob", for: bob)
        let client = GitHubAPIClient(transport: transport)
        return NotificationStore(
            makePoller: {
                [tokens, sleeper, made] account, endpoints, participating, initialPhase, firstFetchNotBefore, onUpdate
                in
                made.withLock { $0.append("\(account.id) \(participating)") }
                return AccountPoller(
                    accountID: account.id, endpoints: endpoints, client: client, tokens: tokens,
                    participating: participating, initialPhase: initialPhase,
                    firstFetchNotBefore: firstFetchNotBefore, sleep: sleeper.sleep, onUpdate: onUpdate)
            }, notifier: notifier, openURL: { [opened] url in opened.withLock { $0.append(url) } },
            preferences: { [settings] in settings.preferences(for: $0) })
    }

    private func status(_ id: AccountID, _ state: TokenState) -> AccountStatus {
        AccountStatus(account: Account(id: id, isActive: id == alice), tokenState: state)
    }

    private nonisolated func gets(_ user: String) -> [URLRequest] {
        transport.requests.filter {
            $0.httpMethod == "GET" && $0.value(forHTTPHeaderField: "Authorization")?.hasSuffix(user) == true
        }
    }

    /// 待っているポーラーを古い順に進めながら、`condition` が満たされるまで待つ（作り直したポーラーの最初の取得の待ちを含む）。
    private func advance(until condition: @MainActor () -> Bool) async {
        for _ in 0..<6 where !condition() {
            sleeper.advance()
            try? await Task.sleep(for: .milliseconds(30))
        }
    }

    private func loadedStore() async -> NotificationStore {
        let store = makeStore()
        store.sync(with: .accounts([status(alice, .ready), status(bob, .ready)]))
        await sleeper.waitForSleeps(2)
        await waitUntil {
            MainActor.assumeIsolated { store.feeds[alice]?.threads.count == 3 && store.feeds[bob]?.threads.count == 3 }
        }
        return store
    }

    @Test func stopsADisabledAccount() async {
        let store = await loadedStore()
        #expect(store.unreadCount == 6)
        notifier.events = []
        store.sync(with: .accounts([status(alice, .ready), status(bob, .disabled)]))
        #expect(store.feeds[bob] == nil)
        #expect(store.unreadCount == 3)
        #expect(notifier.events == ["accountRemoved github.com/bob", "retainOnly github.com/alice"])
        let bobGets = gets("bob").count
        sleeper.advance()
        sleeper.advance()
        await sleeper.waitForSleeps(3)
        #expect(gets("bob").count == bobGets)
        store.stopAll()
    }

    @Test func dropsPendingReadsOfADisabledAccount() async throws {
        let store = makeStore()
        let request = try #require(
            ThreadOpenRequest(userInfo: [
                "host": "github.com", "user": "bob", "threadID": "7", "repository": "octo/app",
            ]))
        store.sync(with: .checking)
        store.openFromNotification(request)
        store.sync(with: .accounts([status(alice, .ready), status(bob, .disabled)]))
        await sleeper.waitForSleeps(1)
        store.sync(with: .accounts([status(alice, .ready), status(bob, .ready)]))
        await sleeper.waitForSleeps(2)
        #expect(opened.value.map(\.absoluteString) == ["https://github.com/octo/app"])
        #expect(transport.requests.allSatisfy { $0.httpMethod != "PATCH" })
        store.stopAll()
    }

    @Test func restartsWithTheNewParticipatingSetting() async {
        let store = await loadedStore()
        let aliceGets = gets("alice").count
        settings.setParticipatingOnly(true, for: alice)
        store.restart(alice)
        #expect(store.feeds[alice] == .loading)
        #expect(notifier.events.last == "resetBaseline github.com/alice")
        #expect(made.value.last == "github.com/alice true")
        // 前の取得から再読み込みと同じ下限（10 秒）がたつまで、最初の取得を待つ
        await sleeper.waitForSleeps(3)
        #expect(gets("alice").count == aliceGets)
        let wait = sleeper.durations.last ?? .zero
        #expect(wait > .seconds(5) && wait <= .seconds(10))
        await advance(until: { store.feeds[alice]?.threads.map(\.id) == ["4", "5"] })
        #expect(store.feeds[alice]?.threads.map(\.id) == ["4", "5"])
        // 作り直したポーラーの最初の取得は条件なしで、gh は呼ばない
        let first = gets("alice")[aliceGets]
        #expect(first.value(forHTTPHeaderField: "If-Modified-Since") == nil)
        #expect(first.url?.query?.contains("participating=true") == true)
        #expect(tokens.refreshCount.value == 0)
        #expect(store.feeds[bob]?.threads.count == 3)
        store.stopAll()
    }

    @Test func dropsLateUpdatesFromTheStoppedPoller() async {
        let store = await loadedStore()
        // 前のポーラーの取得の途中で作り直す
        transport.pausedMethod.value = "GET"
        sleeper.advance()
        await waitUntil { self.gets("alice").count == 2 }
        settings.setParticipatingOnly(true, for: alice)
        store.restart(alice)
        notifier.feeds[alice] = []
        transport.pausedMethod.value = nil
        await advance(until: { store.feeds[alice]?.threads.map(\.id) == ["4", "5"] })
        try? await Task.sleep(for: .milliseconds(50))
        #expect(notifier.feeds[alice]?.allSatisfy { $0 == ["4", "5"] } == true)
        #expect(store.feeds[alice]?.threads.map(\.id) == ["4", "5"])
        store.stopAll()
    }

    @Test func keepsAStoppedAccountStoppedWhenRestarting() async {
        // スコープの足りないトークン
        transport.setHandler { _ in PollerFixture.ok(1...3, scopes: "gist") }
        tokens.set("test-token-alice", for: alice)
        let store = makeStore()
        store.sync(with: .accounts([status(alice, .ready)]))
        await waitUntil { MainActor.assumeIsolated { store.feeds[alice]?.phase == .scopeInsufficient } }
        let count = transport.requests.count
        settings.setParticipatingOnly(true, for: alice)
        store.restart(alice)
        #expect(store.feeds[alice]?.phase == .scopeInsufficient)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(transport.requests.count == count)
        #expect(made.value.last == "github.com/alice true")

        // 再読み込みで、新しい設定のポーラーが再開する
        transport.setHandler { request in
            PollerFixture.ok(request.url?.query?.contains("participating=true") == true ? 4...5 : 1...3)
        }
        tokens.refreshedValue.value = "test-token-alice"
        store.refresh()
        await waitUntil { MainActor.assumeIsolated { store.feeds[alice]?.threads.map(\.id) == ["4", "5"] } }
        #expect(store.feeds[alice]?.threads.map(\.id) == ["4", "5"])
        store.stopAll()
    }

    @Test func keepsTheRateLimitWaitWhenRestarting() async {
        // 最初の取得がレート制限で失敗する
        transport.setHandler { _ in
            HTTPResponse(statusCode: 429, headers: ["Retry-After": "120"])
        }
        tokens.set("test-token-alice", for: alice)
        let store = makeStore()
        store.sync(with: .accounts([status(alice, .ready)]))
        await waitUntil { MainActor.assumeIsolated { store.feeds[alice]?.phase.isRateLimited == true } }
        let count = transport.requests.count
        let sleeps = sleeper.durations.count
        settings.setParticipatingOnly(true, for: alice)
        store.restart(alice)
        #expect(store.feeds[alice]?.phase.isRateLimited == true)
        // 新しいポーラーは、前の再試行の時刻まで待ってから取得する
        await sleeper.waitForSleeps(sleeps + 1)
        #expect(transport.requests.count == count)
        let carried = sleeper.durations.last ?? .zero
        #expect(carried > .seconds(100) && carried <= .seconds(120))
        store.stopAll()
    }

    @Test func keepsTheRateLimitWaitWhenEnabledAgain() async {
        transport.setHandler { _ in HTTPResponse(statusCode: 429, headers: ["Retry-After": "120"]) }
        tokens.set("test-token-alice", for: alice)
        let store = makeStore()
        store.sync(with: .accounts([status(alice, .ready)]))
        await waitUntil { MainActor.assumeIsolated { store.feeds[alice]?.phase.isRateLimited == true } }
        let count = transport.requests.count
        store.sync(with: .accounts([status(alice, .disabled)]))
        let sleeps = sleeper.durations.count
        store.sync(with: .accounts([status(alice, .ready)]))
        // 有効に戻しても、無効にする前の再試行の時刻まで取得しない
        await sleeper.waitForSleeps(sleeps + 1)
        #expect(transport.requests.count == count)
        let carried = sleeper.durations.last ?? .zero
        #expect(carried > .seconds(100) && carried <= .seconds(120))
        store.stopAll()
    }
}
