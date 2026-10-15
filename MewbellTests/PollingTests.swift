import Foundation
import Testing

@testable import Mewbell

struct PollScheduleTests {
    @Test(arguments: [(Int?.some(120), 120), (10, 60), (nil, 60), (60, 60)])
    func waitsForThePollInterval(_ interval: Int?, _ seconds: Int) {
        #expect(PollSchedule.afterSuccess(pollInterval: interval) == .seconds(seconds))
    }

    @Test func waitsUntilTheRateLimitResets() {
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(PollSchedule.afterRateLimit(retryAt: now.addingTimeInterval(300), now: now) == .seconds(300))
        #expect(PollSchedule.afterRateLimit(retryAt: now.addingTimeInterval(10), now: now) == .seconds(60))
        #expect(PollSchedule.afterRateLimit(retryAt: now.addingTimeInterval(-100), now: now) == .seconds(60))
        #expect(PollSchedule.afterRateLimit(retryAt: now.addingTimeInterval(86_400), now: now) == .seconds(3600))
        #expect(PollSchedule.afterRateLimit(retryAt: Date(timeIntervalSince1970: 1e300), now: now) == .seconds(3600))
    }

    @Test func backsOffUpToFifteenMinutes() {
        let durations = (1...7).map { PollSchedule.afterFailure(consecutiveFailures: $0) }
        #expect(durations == [60, 120, 240, 480, 900, 900, 900].map { .seconds($0) })
    }
}

struct AccountPollerTests {
    private let fixture: PollerFixture

    init() throws {
        fixture = try PollerFixture()
    }

    @Test func sendsIfModifiedSinceFromTheSecondFetch() async {
        fixture.respond([PollerFixture.ok(1...3), PollerFixture.notModified])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        #expect(fixture.last?.phase == .loaded(updatedAt: PollerFixture.now))
        #expect(fixture.last?.threads.count == 3)
        fixture.sleeper.advance()
        await fixture.sleeper.waitForSleeps(2)
        #expect(fixture.ifModifiedSince == [nil, "LM-1"])
        // 304 では一覧を変えない
        #expect(fixture.last?.threads.count == 3)
        #expect(fixture.sleeper.durations == [.seconds(60), .seconds(60)])
        fixture.poller.stop()
    }

    @Test func backsOffAndKeepsTheThreadsWhileFailing() async {
        fixture.respond([PollerFixture.ok(1...2)])
        fixture.poller.start()
        for count in 1...3 {
            await fixture.sleeper.waitForSleeps(count)
            fixture.sleeper.advance()
        }
        await fixture.sleeper.waitForSleeps(4)
        #expect(fixture.sleeper.durations == [60, 60, 120, 240].map { .seconds($0) })
        #expect(fixture.last?.threads.count == 2)
        #expect(
            fixture.last?.phase
                == .retrying(nextAttempt: PollerFixture.now.addingTimeInterval(240), rateLimited: false))
        // 応答を差し替えてから待ちを進める（先に進めると、次の取得が前の応答を受け取ることがある）
        fixture.respond([PollerFixture.ok(1...1)])
        fixture.sleeper.advance()
        await fixture.sleeper.waitForSleeps(5)
        #expect(fixture.sleeper.durations.last == .seconds(60))
        fixture.poller.stop()
    }

    /// 待ち時間のヘッダーが無い二次レート制限は、失敗と同じく延ばしながら待ち、レート制限として扱う
    @Test func backsOffASecondaryRateLimitWithoutAWait() async {
        let secondary = FakeHTTPTransport.secondaryRateLimit(headers: ["X-OAuth-Scopes": "repo"])
        fixture.respond([PollerFixture.ok(1...2), secondary, secondary, PollerFixture.ok(1...1)])
        fixture.poller.start()
        for count in 1...2 {
            await fixture.sleeper.waitForSleeps(count)
            fixture.sleeper.advance()
        }
        await fixture.sleeper.waitForSleeps(3)
        #expect(fixture.sleeper.durations == [60, 60, 120].map { .seconds($0) })
        #expect(fixture.last?.threads.count == 2)
        #expect(
            fixture.last?.phase
                == .retrying(nextAttempt: PollerFixture.now.addingTimeInterval(120), rateLimited: true))
        #expect(fixture.last?.diagnostics.lastFetchFailure?.kind == .rateLimited)
        // 成功の後は 60 秒からに戻る
        fixture.sleeper.advance()
        await fixture.sleeper.waitForSleeps(4)
        #expect(fixture.sleeper.durations.last == .seconds(60))
        fixture.poller.stop()
    }

    @Test func refreshesTheTokenOnceAfter401() async {
        fixture.tokens.refreshedValue.value = "test-token-alice-2"
        fixture.respond([PollerFixture.ok(1...1), HTTPResponse(statusCode: 401), PollerFixture.ok(1...2)])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        fixture.sleeper.advance()
        await fixture.sleeper.waitForSleeps(2)
        #expect(fixture.tokens.refreshCount.value == 1)
        #expect(fixture.ifModifiedSince == [nil, "LM-1", nil])
        #expect(
            fixture.authorizations
                == ["Bearer test-token-alice", "Bearer test-token-alice", "Bearer test-token-alice-2"])
        #expect(fixture.last?.threads.count == 2)
        fixture.poller.stop()
    }

    @Test func stopsAsUnauthorizedWhenStill401AfterRefreshing() async {
        fixture.tokens.refreshedValue.value = "test-token-alice-2"
        fixture.respond([HTTPResponse(statusCode: 401), HTTPResponse(statusCode: 401), PollerFixture.ok(1...1)])
        fixture.poller.start()
        await waitUntil { self.fixture.last?.phase == .unauthorized }
        #expect(fixture.last?.phase == .unauthorized)
        #expect(fixture.last?.threads.isEmpty == true)
        #expect(fixture.tokens.refreshCount.value == 1)
        #expect(fixture.tokens.discardCount.value == 1)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(fixture.transport.requests.count == 2)
        #expect(fixture.sleeper.durations.isEmpty)
    }

    @Test func stopsWhenA403SaysTheScopesAreInsufficient() async {
        fixture.respond([HTTPResponse(statusCode: 403, headers: ["X-OAuth-Scopes": "gist, read:org"])])
        fixture.poller.start()
        await waitUntil { self.fixture.last?.phase == .scopeInsufficient }
        #expect(fixture.last?.phase == .scopeInsufficient)
        #expect(fixture.sleeper.durations.isEmpty)
        #expect(fixture.last?.diagnostics.scopes == OAuthScopes(header: "gist, read:org"))
        #expect(fixture.last?.diagnostics.lastFetchFailure?.kind == .httpStatus(403))
    }

    @Test func keepsRetryingAForbiddenResponseWithoutScopes() async {
        fixture.respond([HTTPResponse(statusCode: 403)])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        #expect(fixture.sleeper.durations == [.seconds(60)])
        fixture.poller.stop()
    }

    @Test func startsTheBackoffOverAfterResuming() async {
        // 通信の失敗が 2 回続いた後、スコープ不足で止まる
        fixture.respond([])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        fixture.sleeper.advance()
        await fixture.sleeper.waitForSleeps(2)
        fixture.respond([PollerFixture.ok(1...1, scopes: "gist")])
        fixture.sleeper.advance()
        await waitUntil { self.fixture.last?.phase == .scopeInsufficient }
        // 再開した最初の取得が失敗したら、60 秒から数え直す
        fixture.tokens.refreshedValue.value = "test-token-alice-2"
        fixture.respond([])
        fixture.poller.resume()
        await fixture.sleeper.waitForSleeps(3)
        #expect(fixture.sleeper.durations == [60, 120, 60].map { .seconds($0) })
        fixture.poller.stop()
    }

    @Test func waitsWithoutSendingWhenThereIsNoToken() async {
        await fixture.tokens.discardToken(for: PollerFixture.alice)
        fixture.respond([PollerFixture.ok(1...1)])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        fixture.sleeper.advance()
        await fixture.sleeper.waitForSleeps(2)
        #expect(fixture.transport.requests.isEmpty)
        // 失敗の回数に数えないので、待ち時間は延びない
        #expect(fixture.sleeper.durations == [.seconds(60), .seconds(60)])
        #expect(
            fixture.last?.phase == .retrying(nextAttempt: PollerFixture.now.addingTimeInterval(60), rateLimited: false))
        fixture.tokens.set("test-token-alice", for: PollerFixture.alice)
        fixture.sleeper.advance()
        await fixture.sleeper.waitForSleeps(3)
        #expect(fixture.transport.requests.count == 1)
        #expect(fixture.last?.phase == .loaded(updatedAt: PollerFixture.now))
        fixture.poller.stop()
    }

    @Test func stopsWhenTheScopesAreInsufficientAndResumesLater() async {
        fixture.respond([PollerFixture.ok(1...3, scopes: "gist, read:org")])
        fixture.poller.start()
        await waitUntil { self.fixture.last?.phase == .scopeInsufficient }
        #expect(fixture.last?.threads.isEmpty == true)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(fixture.transport.requests.count == 1)
        #expect(fixture.sleeper.durations.isEmpty)
        #expect(fixture.last?.diagnostics.scopes == OAuthScopes(header: "gist, read:org"))

        fixture.tokens.refreshedValue.value = "test-token-alice-2"
        fixture.respond([PollerFixture.ok(1...3)])
        let updatesBefore = fixture.updates.value.count
        fixture.poller.resume()
        await fixture.sleeper.waitForSleeps(1)
        #expect(fixture.tokens.refreshCount.value == 1)
        // 再開の間は最初の取得中を出す（Diagnostics の値は持ち越すが、前のトークンのスコープは捨てる）
        let loading = fixture.updates.value.dropFirst(updatesBefore).first { $0.phase == .loading }
        #expect(loading?.threads.isEmpty == true)
        #expect(loading?.diagnostics.scopes == nil)
        #expect(fixture.last?.threads.count == 3)
        #expect(fixture.ifModifiedSince == [nil, nil])
        #expect(fixture.authorizations.last == "Bearer test-token-alice-2")
        fixture.poller.stop()
    }
}

@MainActor
struct NotificationStoreTests {
    /// `bad-token` には 401、それ以外には 200 を返す
    private let transport = FakeHTTPTransport { request in
        request.value(forHTTPHeaderField: "Authorization") == "Bearer bad-token"
            ? HTTPResponse(statusCode: 401) : PollerFixture.ok(1...1)
    }
    private let tokens = FakeTokenProvider()
    private let sleeper = ManualSleeper()
    private let created = LockedValue<[AccountID]>([])

    private func makeStore() -> NotificationStore {
        let client = GitHubAPIClient(transport: transport)
        return NotificationStore(
            makePoller: { [tokens, sleeper, created] account, endpoints, _, _, _, onUpdate in
                created.withLock { $0.append(account.id) }
                return AccountPoller(
                    accountID: account.id, endpoints: endpoints, client: client, tokens: tokens, sleep: sleeper.sleep,
                    onUpdate: onUpdate)
            }, openURL: { _ in })
    }

    private func status(_ user: String, _ state: TokenState, host: String = "github.com") -> AccountStatus {
        AccountStatus(account: Account(id: AccountID(host: host, user: user), isActive: true), tokenState: state)
    }

    private let alice = AccountID(host: "github.com", user: "alice")
    private let bob = AccountID(host: "github.com", user: "bob")

    @Test func startsPollersOnlyForReadyAccounts() async {
        tokens.set("test-token-alice", for: alice)
        let store = makeStore()
        store.sync(with: .accounts([status("alice", .ready), status("bob", .fetching)]))
        #expect(created.value == [alice])
        #expect(store.feeds[bob] == nil)
        await waitUntil { MainActor.assumeIsolated { store.feeds[alice]?.threads.count == 1 } }
        #expect(store.feeds[alice]?.threads.count == 1)
        store.stopAll()
    }

    @Test func stopsPollersForAccountsThatAreGone() async {
        tokens.set("test-token-alice", for: alice)
        tokens.set("test-token-bob", for: bob)
        let store = makeStore()
        store.sync(with: .accounts([status("alice", .ready), status("bob", .ready)]))
        await sleeper.waitForSleeps(2)
        // トークンを取れなくなっただけのアカウントのポーラーは残す
        store.sync(with: .accounts([status("alice", .unavailable)]))
        #expect(store.feeds[bob] == nil)
        #expect(store.feeds[alice]?.threads.count == 1)
        store.sync(with: .accounts([status("alice", .ready)]))
        #expect(created.value == [alice, bob])
        store.sync(with: .notLoggedIn)
        #expect(store.feeds.isEmpty)
        store.sync(with: .accounts([status("alice", .ready)]))
        #expect(store.feeds[alice] == .loading)
        store.stopAll()
    }

    /// alice のトークンが 401 になり、取り直せずに「認証エラー」で止まった store を作る。
    private func storeWithUnauthorizedAlice(otherAccounts: [AccountStatus] = []) async -> NotificationStore {
        tokens.set("bad-token", for: alice)
        let store = makeStore()
        store.sync(with: .accounts([status("alice", .ready)] + otherAccounts))
        await waitUntil { MainActor.assumeIsolated { store.feeds[alice]?.phase == .unauthorized } }
        return store
    }

    @Test func keepsStoppedPollersWhileTheTokenIsFetchedAgain() async {
        let store = await storeWithUnauthorizedAlice()
        #expect(store.feeds[alice]?.phase == .unauthorized)
        // ポップオーバーを開いた読み直しで、トークンを持たない alice が取得中を経て「使える」に戻る
        store.sync(with: .accounts([status("alice", .fetching), status("bob", .fetching)]))
        store.sync(with: .accounts([status("alice", .unavailable), status("bob", .fetching)]))
        tokens.set("bad-token", for: alice)
        store.sync(with: .accounts([status("alice", .ready), status("bob", .fetching)]))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(created.value == [alice])
        #expect(store.feeds[alice]?.phase == .unauthorized)
        #expect(transport.requests.count == 1)
        #expect(tokens.refreshCount.value == 1)
    }

    @Test func refreshResumesStoppedPollers() async {
        tokens.set("test-token-bob", for: bob)
        let store = await storeWithUnauthorizedAlice(otherAccounts: [status("bob", .ready)])
        await sleeper.waitForSleeps(1)
        tokens.refreshedValue.value = "test-token-alice"
        store.refresh()
        #expect(store.feeds[alice]?.phase == .loading)
        #expect(store.feeds[alice]?.threads.isEmpty == true)
        await waitUntil { MainActor.assumeIsolated { store.feeds[alice]?.threads.count == 1 } }
        // トークンを取り直すのは止まっていた alice だけ。bob は前の取得から 10 秒の下限を待っている
        #expect(tokens.refreshCount.value == 2)
        #expect(transport.requests.count == 3)
        #expect(store.isRefreshing)
        #expect(store.feeds[alice]?.threads.count == 1)
        store.stopAll()
    }
}
