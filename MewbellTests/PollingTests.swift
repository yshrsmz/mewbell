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
    }

    @Test func backsOffUpToFifteenMinutes() {
        let durations = (1...7).map { PollSchedule.afterFailure(consecutiveFailures: $0) }
        #expect(durations == [60, 120, 240, 480, 900, 900, 900].map { .seconds($0) })
    }
}

/// `AccountPoller` を偽のトランスポート・トークン・時計で動かす。
final class PollerFixture: Sendable {
    static let alice = AccountID(host: "github.com", user: "alice")
    static let now = Date(timeIntervalSince1970: 1_791_460_800)

    let transport = FakeHTTPTransport()
    let tokens = FakeTokenProvider([alice: "test-token-alice"])
    let sleeper = ManualSleeper()
    let updates = LockedValue<[FeedState]>([])
    let poller: AccountPoller

    init() throws {
        let updates = updates
        let now = Self.now
        poller = AccountPoller(
            accountID: Self.alice, endpoints: try #require(APIEndpoints(host: "github.com")),
            client: GitHubAPIClient(transport: transport, now: { now }), tokens: tokens, sleep: sleeper.sleep,
            now: { now }, onUpdate: { state in updates.withLock { $0.append(state) } })
    }

    var last: FeedState? { updates.value.last }

    func respond(_ responses: [HTTPResponse]) {
        let queue = LockedValue(responses)
        transport.setHandler { _ throws(TransportError) in
            guard let next = queue.withLock({ $0.isEmpty ? nil : $0.removeFirst() }) else {
                throw .network(code: URLError.Code.notConnectedToInternet.rawValue)
            }
            return next
        }
    }

    static func ok(_ ids: ClosedRange<Int>, lastModified: String = "LM-1", scopes: String = "repo") -> HTTPResponse {
        HTTPResponse(
            statusCode: 200,
            headers: ["Last-Modified": lastModified, "X-OAuth-Scopes": scopes, "X-Poll-Interval": "60"],
            body: FakeHTTPTransport.page(ids))
    }

    var ifModifiedSince: [String?] {
        transport.requests.map { $0.value(forHTTPHeaderField: "If-Modified-Since") }
    }

    var authorizations: [String?] {
        transport.requests.map { $0.value(forHTTPHeaderField: "Authorization") }
    }
}

struct AccountPollerTests {
    private let fixture: PollerFixture

    init() throws {
        fixture = try PollerFixture()
    }

    @Test func sendsIfModifiedSinceFromTheSecondFetch() async {
        fixture.respond([PollerFixture.ok(1...3), HTTPResponse(statusCode: 304)])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        #expect(
            fixture.last
                == FeedState(phase: .loaded(updatedAt: PollerFixture.now), threads: fixture.last?.threads ?? []))
        #expect(fixture.last?.threads.count == 3)
        fixture.sleeper.advance()
        await fixture.sleeper.waitForSleeps(2)
        #expect(fixture.ifModifiedSince == [nil, "LM-1"])
        // 304 では一覧を変えない
        #expect(fixture.last?.threads.count == 3)
        #expect(fixture.sleeper.durations == [.seconds(60), .seconds(60)])
        fixture.poller.stop()
    }

    @Test func keepsLastModifiedWhenALaterPageFails() async {
        let partial = HTTPResponse(
            statusCode: 200,
            headers: [
                "Last-Modified": "LM-2", "X-OAuth-Scopes": "repo",
                "Link": #"<https://api.github.com/notifications?page=2>; rel="next""#,
            ],
            body: FakeHTTPTransport.page(1...1))
        fixture.respond([PollerFixture.ok(1...1), partial])  // 2 ページ目は通信の失敗
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        fixture.sleeper.advance()
        await fixture.sleeper.waitForSleeps(2)
        fixture.respond([HTTPResponse(statusCode: 304)])
        fixture.sleeper.advance()
        await fixture.sleeper.waitForSleeps(3)
        #expect(fixture.ifModifiedSince == [nil, "LM-1", nil, "LM-1"])
        fixture.poller.stop()
    }

    @Test func backsOffAndKeepsTheThreadsWhileFailing() async {
        fixture.respond([PollerFixture.ok(1...2)])
        fixture.poller.start()
        for count in 1...4 {
            await fixture.sleeper.waitForSleeps(count)
            fixture.sleeper.advance()
        }
        await fixture.sleeper.waitForSleeps(4)
        #expect(fixture.sleeper.durations == [60, 60, 120, 240].map { .seconds($0) })
        #expect(fixture.last?.threads.count == 2)
        #expect(
            fixture.last?.phase
                == .retrying(nextAttempt: PollerFixture.now.addingTimeInterval(240), rateLimited: false))
        fixture.respond([PollerFixture.ok(1...1)])
        await fixture.sleeper.waitForSleeps(5)
        #expect(fixture.sleeper.durations.last == .seconds(60))
        fixture.poller.stop()
    }

    @Test func waitsForTheRateLimit() async {
        fixture.respond([HTTPResponse(statusCode: 403, headers: ["Retry-After": "300"])])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        #expect(fixture.sleeper.durations == [.seconds(300)])
        if case .retrying(_, let rateLimited) = fixture.last?.phase {
            #expect(rateLimited)
        } else {
            Issue.record("unexpected phase \(String(describing: fixture.last?.phase))")
        }
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
        #expect(fixture.last == FeedState(phase: .unauthorized, threads: []))
        #expect(fixture.tokens.refreshCount.value == 1)
        #expect(fixture.tokens.discardCount.value == 1)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(fixture.transport.requests.count == 2)
        #expect(fixture.sleeper.durations.isEmpty)
    }

    @Test func waitsWithoutSendingWhenThereIsNoToken() async {
        await fixture.tokens.discardToken(for: PollerFixture.alice)
        fixture.respond([PollerFixture.ok(1...1)])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        #expect(fixture.transport.requests.isEmpty)
        #expect(fixture.sleeper.durations == [.seconds(60)])
        #expect(
            fixture.last?.phase == .retrying(nextAttempt: PollerFixture.now.addingTimeInterval(60), rateLimited: false))
        fixture.tokens.set("test-token-alice", for: PollerFixture.alice)
        fixture.sleeper.advance()
        await fixture.sleeper.waitForSleeps(2)
        #expect(fixture.transport.requests.count == 1)
        #expect(fixture.last?.phase == .loaded(updatedAt: PollerFixture.now))
        fixture.poller.stop()
    }

    @Test func stopsAsUnauthorizedWhenTheTokenCannotBeRefreshed() async {
        fixture.respond([HTTPResponse(statusCode: 401)])
        fixture.poller.start()
        await waitUntil { self.fixture.last?.phase == .unauthorized }
        #expect(fixture.tokens.refreshCount.value == 1)
        #expect(fixture.transport.requests.count == 1)
    }

    @Test func stopsWhenTheScopesAreInsufficientAndResumesLater() async {
        fixture.respond([PollerFixture.ok(1...3, scopes: "gist, read:org")])
        fixture.poller.start()
        await waitUntil { self.fixture.last?.phase == .scopeInsufficient }
        #expect(fixture.last?.threads.isEmpty == true)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(fixture.transport.requests.count == 1)
        #expect(fixture.sleeper.durations.isEmpty)

        fixture.tokens.refreshedValue.value = "test-token-alice-2"
        fixture.respond([PollerFixture.ok(1...3)])
        fixture.poller.resume()
        await fixture.sleeper.waitForSleeps(1)
        #expect(fixture.tokens.refreshCount.value == 1)
        #expect(fixture.updates.value.contains(.loading))
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
        return NotificationStore { [tokens, sleeper, created] account, endpoints, onUpdate in
            created.withLock { $0.append(account.id) }
            return AccountPoller(
                accountID: account.id, endpoints: endpoints, client: client, tokens: tokens, sleep: sleeper.sleep,
                onUpdate: onUpdate)
        }
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

    @Test func stopsPollersForAccountsThatAreGoneOrUnavailable() async {
        tokens.set("test-token-alice", for: alice)
        tokens.set("test-token-bob", for: bob)
        let store = makeStore()
        store.sync(with: .accounts([status("alice", .ready), status("bob", .ready)]))
        await sleeper.waitForSleeps(2)
        store.sync(with: .accounts([status("alice", .unavailable)]))
        #expect(store.feeds.isEmpty)
        store.sync(with: .accounts([status("alice", .ready)]))
        #expect(store.feeds[alice] == .loading)
        store.sync(with: .notLoggedIn)
        #expect(store.feeds.isEmpty)
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
        tokens.set("bad-token", for: alice)
        store.sync(with: .accounts([status("alice", .ready), status("bob", .fetching)]))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(created.value == [alice])
        #expect(store.feeds[alice]?.phase == .unauthorized)
        #expect(transport.requests.count == 1)
        #expect(tokens.refreshCount.value == 1)
    }

    @Test func keepsRunningPollersWhileTheTokenIsFetched() async {
        tokens.set("test-token-alice", for: alice)
        let store = makeStore()
        store.sync(with: .accounts([status("alice", .ready)]))
        await sleeper.waitForSleeps(1)
        store.sync(with: .accounts([status("alice", .fetching)]))
        store.sync(with: .accounts([status("alice", .ready)]))
        #expect(created.value == [alice])
        #expect(store.feeds[alice]?.threads.count == 1)
        #expect(transport.requests.count == 1)
        store.stopAll()
    }

    @Test func resumesOnlyStoppedPollers() async {
        tokens.set("test-token-bob", for: bob)
        let store = await storeWithUnauthorizedAlice(otherAccounts: [status("bob", .ready)])
        await sleeper.waitForSleeps(1)
        tokens.refreshedValue.value = "test-token-alice"
        store.resumeStopped()
        #expect(store.feeds[alice] == .loading)
        await sleeper.waitForSleeps(2)
        #expect(tokens.refreshCount.value == 2)
        #expect(transport.requests.count == 3)
        #expect(store.feeds[alice]?.threads.count == 1)
        store.stopAll()
    }

    @Test func ignoresUpdatesFromStoppedPollers() async {
        tokens.set("test-token-alice", for: alice)
        transport.setHandler { _ throws(TransportError) in
            Thread.sleep(forTimeInterval: 0.1)
            return PollerFixture.ok(1...1)
        }
        let store = makeStore()
        store.sync(with: .accounts([status("alice", .ready)]))
        await waitUntil { self.transport.requests.count == 1 }
        store.sync(with: .notLoggedIn)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(store.feeds.isEmpty)
    }
}
