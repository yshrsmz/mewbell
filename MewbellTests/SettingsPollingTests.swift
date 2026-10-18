import Foundation
import Testing

@testable import Mewbell

/// `ThreadNotifying` への呼び出しを記録する。
@MainActor
final class RecordingNotifier: ThreadNotifying {
    var events: [String] = []
    /// `baselineSet` の `keeping`（並べ替えたもの）と `threadsChanged` の `posted` のスレッドの ID（アカウントごと、届いた順）
    var feeds: [AccountID: [[String]]] = [:]
    /// `threadsChanged` に渡った値（アカウントごと、届いた順）
    var changes: [AccountID: [(posted: [String], retracted: Set<String>)]] = [:]

    func baselineSet(for account: AccountID, keeping threadIDs: Set<String>) {
        events.append("baselineSet \(account) \(threadIDs.sorted().joined(separator: ","))")
        feeds[account, default: []].append(threadIDs.sorted())
    }

    func threadsChanged(for account: AccountID, posted: [NotificationThread], retracted: Set<String>) {
        events.append("threadsChanged \(account)")
        feeds[account, default: []].append(posted.map(\.id))
        changes[account, default: []].append((posted.map(\.id), retracted))
    }

    func threadsRemoved(_ threadIDs: Set<String>, for account: AccountID) {
        events.append("threadsRemoved \(account) \(threadIDs.sorted().joined(separator: ","))")
    }

    func retractAll(for account: AccountID) {
        events.append("retractAll \(account)")
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
                [tokens, sleeper, made] account, endpoints, participating, initialPhase, carriedWait, onUpdate
                in
                made.withLock { $0.append("\(account.id) \(participating)") }
                return AccountPoller(
                    accountID: account.id, endpoints: endpoints, client: client, tokens: tokens,
                    participating: participating, initialPhase: initialPhase,
                    carriedWait: carriedWait, sleep: sleeper.sleep, onUpdate: onUpdate)
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

    /// 待っているポーラーを古い順に 1 つずつ起こし、起こしたポーラーが次の待ちに入るまで待ちながら、`condition` が満たされるまで進める
    /// （作り直したポーラーの最初の取得の待ちを含む）。待っているポーラーがいて、起こしたポーラーが次の待ちに入る場面でだけ使う。
    /// 満たされないまま 6 回起こしたら、呼び出し元の位置に Issue を記録する。
    private func advance(
        until condition: @MainActor () -> Bool, sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        for _ in 0..<6 where !condition() {
            let sleeps = sleeper.durations.count
            sleeper.advance()
            await sleeper.waitForSleeps(sleeps + 1, sourceLocation: sourceLocation)
        }
        if !condition() {
            Issue.record("待ちを 6 回進めても条件が満たされなかった", sourceLocation: sourceLocation)
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
        #expect(notifier.events == ["retractAll github.com/bob", "retainOnly github.com/alice"])
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
        notifier.events = []
        store.restart(alice)
        #expect(store.feeds[alice] == .loading)
        // 出ている通知は取り下げず、次の基準の取得で今の一覧に無いものだけを取り下げる
        #expect(notifier.events.isEmpty)
        #expect(made.value.last == "github.com/alice true")
        // 前の取得から再読み込みと同じ下限（10 秒）がたつまで、最初の取得を待つ
        await sleeper.waitForSleeps(3)
        #expect(gets("alice").count == aliceGets)
        let wait = sleeper.durations.last ?? .zero
        #expect(wait > .seconds(5) && wait <= .seconds(10))
        await advance(until: { store.feeds[alice]?.threads.map(\.id) == ["4", "5"] })
        #expect(store.feeds[alice]?.threads.map(\.id) == ["4", "5"])
        // 作り直した後の最初の取得は基準
        #expect(notifier.events.filter { $0.contains("alice") } == ["baselineSet github.com/alice 4,5"])
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
        // alice と bob のどちらが先に寝たかは決まらないので、両方を起こす
        sleeper.advance()
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
        // 有効に戻しても、無効にする前の再試行の時刻まで取得せず、レート制限の待ちとして表示する
        await sleeper.waitForSleeps(sleeps + 1)
        #expect(transport.requests.count == count)
        let carried = sleeper.durations.last ?? .zero
        #expect(carried > .seconds(100) && carried <= .seconds(120))
        #expect(store.feeds[alice]?.phase.isRateLimited == true)
        // 再読み込みでも早めない
        store.refresh()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(transport.requests.count == count)
        // 待ちの途中で作り直しても、レート制限の待ちとして表示し、待ちは縮まない
        settings.setParticipatingOnly(true, for: alice)
        store.restart(alice)
        #expect(store.feeds[alice]?.phase.isRateLimited == true)
        await sleeper.waitForSleeps(sleeps + 2)
        #expect(transport.requests.count == count)
        let again = sleeper.durations.last ?? .zero
        #expect(again > .seconds(100) && again <= .seconds(120))
        store.stopAll()
    }

    @Test func letsAReloadSkipTheCarriedWait() async {
        let store = await loadedStore()
        let aliceGets = gets("alice").count
        settings.setParticipatingOnly(true, for: alice)
        store.restart(alice)
        await sleeper.waitForSleeps(3)
        #expect(gets("alice").count == aliceGets)
        // 作り直したポーラーが最初の取得を待っている間でも、再読み込みで取得する。ただし前の取得の開始から 10 秒は空ける
        store.refresh()
        await sleeper.waitForSleeps(4)
        #expect(gets("alice").count == aliceGets)
        let floor = sleeper.durations.last ?? .zero
        #expect(floor > .zero && floor <= .seconds(10))
        await advance(until: { self.gets("alice").count > aliceGets })
        #expect(gets("alice").count > aliceGets)
        store.stopAll()
    }
}

struct CarriedWaitTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func carriesTheRetryOrTheReloadFloor() {
        let rateLimited = FeedState(phase: .retrying(nextAttempt: now + 120, rateLimited: true), threads: [])
        #expect(
            CarriedWait(from: rateLimited, now: now)
                == CarriedWait(until: now + 120, rateLimited: true, lastAttemptStartedAt: nil))
        let loaded = FeedState(phase: .loaded(updatedAt: now - 2), threads: [])
        #expect(
            CarriedWait(from: loaded, now: now)
                == CarriedWait(until: now + 8, rateLimited: false, lastAttemptStartedAt: now - 2))
        #expect(CarriedWait(from: FeedState(phase: .scopeInsufficient, threads: []), now: now) == nil)
    }

    @Test func mergesToTheLaterWait() {
        let rateLimited = CarriedWait(until: now + 120, rateLimited: true, lastAttemptStartedAt: nil)
        let floor = CarriedWait(until: now + 10, rateLimited: false, lastAttemptStartedAt: now)
        #expect(
            rateLimited.merged(with: floor)
                == CarriedWait(until: now + 120, rateLimited: true, lastAttemptStartedAt: now))
        #expect(floor.merged(with: nil) == floor)
    }
}
