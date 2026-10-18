import Foundation
import Testing

@testable import Mewbell

/// 再読み込み（`AccountPoller.refreshNow`）で、次の予定を待たずに条件なしで取得する。
struct RefreshNowTests {
    private let fixture: PollerFixture

    init() throws {
        fixture = try PollerFixture()
    }

    /// 最初の取得を終えて、次の取得を待っているポーラー。
    private func startAndWait() async {
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
    }

    @Test func wakesTheWaitAndFetchesWithoutIfModifiedSince() async {
        fixture.respond([PollerFixture.ok(1...1), PollerFixture.ok(1...2, lastModified: "LM-2")])
        await startAndWait()
        fixture.moveClock(by: 20)
        await fixture.poller.refreshNow()
        #expect(fixture.ifModifiedSince == [nil, nil])
        #expect(fixture.lastIDs == ["1", "2"])
        // 押した後の成功からは、また 60 秒待つ
        await fixture.sleeper.waitForSleeps(2)
        #expect(fixture.sleeper.durations == [.seconds(60), .seconds(60)])
        fixture.poller.stop()
    }

    @Test func waitsUntilTenSecondsAfterThePreviousFetch() async {
        fixture.respond([PollerFixture.ok(1...1), PollerFixture.ok(1...2)])
        await startAndWait()
        fixture.moveClock(by: 3)
        let refresh = Task { await fixture.poller.refreshNow() }
        await fixture.sleeper.waitForSleeps(2)
        #expect(fixture.sleeper.durations == [.seconds(60), .seconds(7)])
        #expect(fixture.transport.requests.count == 1)
        // 早めた取得の予定時刻を Diagnostics に出す
        #expect(fixture.last?.diagnostics.nextFetchAt == PollerFixture.now.addingTimeInterval(10))
        fixture.advance(by: 7)
        await refresh.value
        #expect(fixture.ifModifiedSince == [nil, nil])
        fixture.poller.stop()
    }

    @Test func fetchesOnceMoreAfterAFetchInFlight() async {
        fixture.respond([PollerFixture.ok(1...1), PollerFixture.notModified, PollerFixture.ok(1...2)])
        await startAndWait()
        fixture.transport.pausedMethod.value = "GET"
        fixture.advance(by: 60)
        await waitUntil { fixture.transport.requests.count == 2 }
        let refresh = Task { await fixture.poller.refreshNow() }
        await fixture.waitForPendingRefresh()
        fixture.transport.pausedMethod.value = nil
        // 取得中の分が終わった後は、その取得の開始から 10 秒の下限だけ待つ
        await fixture.sleeper.waitForSleeps(2)
        #expect(fixture.sleeper.durations == [.seconds(60), .seconds(10)])
        #expect(fixture.transport.requests.count == 2)
        fixture.advance(by: 10)
        await refresh.value
        #expect(fixture.ifModifiedSince == [nil, "LM-1", nil])
        #expect(fixture.lastIDs == ["1", "2"])
        fixture.poller.stop()
    }

    /// レート制限の待ちは早めない。待ち時間のヘッダーが無い二次レート制限（失敗と同じく延ばした待ち）も同じ
    @Test(arguments: [
        (HTTPResponse(statusCode: 403, headers: ["Retry-After": "300"]), 300),
        (FakeHTTPTransport.secondaryRateLimit(), 60),
    ])
    func doesNotHastenARateLimitedWait(_ rateLimit: HTTPResponse, _ wait: Int) async {
        fixture.respond([PollerFixture.ok(1...1), rateLimit, PollerFixture.notModified])
        await startAndWait()
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(2)
        fixture.moveClock(by: 20)
        await fixture.poller.refreshNow()
        #expect(fixture.transport.requests.count == 2)
        #expect(fixture.sleeper.durations == [.seconds(60), .seconds(wait)])
        // 早めはしないが、次の取得は条件なしになる
        fixture.advance(by: TimeInterval(wait - 20))
        await fixture.sleeper.waitForSleeps(3)
        #expect(fixture.ifModifiedSince == [nil, "LM-1", nil])
        fixture.poller.stop()
    }

    @Test func doesNotHastenARateLimitReturnedByTheFetchInFlight() async {
        fixture.respond([
            PollerFixture.ok(1...1), HTTPResponse(statusCode: 403, headers: ["Retry-After": "300"]),
            PollerFixture.notModified,
        ])
        await startAndWait()
        fixture.transport.pausedMethod.value = "GET"
        fixture.advance(by: 60)
        await waitUntil { fixture.transport.requests.count == 2 }
        let refresh = Task { await fixture.poller.refreshNow() }
        await fixture.waitForPendingRefresh()
        fixture.transport.pausedMethod.value = nil
        await refresh.value
        await fixture.sleeper.waitForSleeps(2)
        #expect(fixture.sleeper.durations == [.seconds(60), .seconds(300)])
        #expect(fixture.transport.requests.count == 2)
        fixture.poller.stop()
    }

    @Test func fetchesOnceMoreWhenPressedDuringTheFetchAfterARateLimit() async {
        fixture.respond([
            PollerFixture.ok(1...1), HTTPResponse(statusCode: 403, headers: ["Retry-After": "300"]),
            PollerFixture.notModified, PollerFixture.ok(1...2),
        ])
        await startAndWait()
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(2)
        fixture.transport.pausedMethod.value = "GET"
        fixture.advance(by: 300)
        await waitUntil { fixture.transport.requests.count == 3 }
        let refresh = Task { await fixture.poller.refreshNow() }
        await fixture.waitForPendingRefresh()
        fixture.transport.pausedMethod.value = nil
        await fixture.sleeper.waitForSleeps(3)
        #expect(fixture.sleeper.durations == [.seconds(60), .seconds(300), .seconds(10)])
        fixture.advance(by: 10)
        await refresh.value
        #expect(fixture.lastIDs == ["1", "2"])
        fixture.poller.stop()
    }

    @Test func doesNotResumeAfterStop() async {
        fixture.respond([HTTPResponse(statusCode: 401), PollerFixture.ok(1...1)])
        fixture.poller.start()
        await waitUntil { fixture.last?.phase == .unauthorized }
        fixture.poller.stop()
        fixture.tokens.refreshedValue.value = "test-token-alice"
        await fixture.poller.refreshNow()
        try? await Task.sleep(for: .milliseconds(20))
        // 取り除いたアカウントのトークンを取り直さず、取得もしない
        #expect(fixture.tokens.refreshCount.value == 1)
        #expect(fixture.transport.requests.count == 1)
    }

    @Test func resumesAStoppedPollerAndWaitsForItsFirstFetch() async {
        fixture.respond([HTTPResponse(statusCode: 401), PollerFixture.ok(1...2)])
        fixture.poller.start()
        await waitUntil { fixture.last?.phase == .unauthorized }
        fixture.tokens.refreshedValue.value = "test-token-alice"
        await fixture.poller.refreshNow()
        #expect(fixture.lastIDs == ["1", "2"])
        #expect(fixture.tokens.refreshCount.value == 2)
        fixture.poller.stop()
    }

    @Test func returnsWhenAStoppedPollerCannotResume() async {
        fixture.respond([HTTPResponse(statusCode: 401)])
        fixture.poller.start()
        await waitUntil { fixture.last?.phase == .unauthorized }
        await fixture.poller.refreshNow()
        #expect(fixture.last?.phase == .unauthorized)
        #expect(fixture.transport.requests.count == 1)
    }

    @Test func returnsWhenStoppedWhileWaiting() async {
        fixture.respond([PollerFixture.ok(1...1)])
        await startAndWait()
        let refresh = Task { await fixture.poller.refreshNow() }
        await fixture.sleeper.waitForSleeps(2)
        fixture.poller.stop()
        await refresh.value
        #expect(fixture.transport.requests.count == 1)
    }

    @Test func returnsWithoutALoop() async {
        await fixture.poller.refreshNow()
        #expect(fixture.transport.requests.isEmpty)
    }

    @Test func waitsForTheRetryAfterRefreshingTheToken() async {
        fixture.respond([PollerFixture.ok(1...1), HTTPResponse(statusCode: 401), PollerFixture.ok(1...3)])
        fixture.tokens.refreshedValue.value = "test-token-alice-2"
        await startAndWait()
        fixture.moveClock(by: 20)
        await fixture.poller.refreshNow()
        #expect(fixture.transport.requests.count == 3)
        #expect(fixture.lastIDs == ["1", "2", "3"])
        fixture.poller.stop()
    }
}

/// 再読み込み（`NotificationStore.refresh`）で、全アカウントをすぐ取得し、終わるまで `isRefreshing` を立てる。
@MainActor
struct NotificationStoreRefreshTests {
    private let transport = FakeHTTPTransport { _ in PollerFixture.ok(1...1) }
    private let tokens = FakeTokenProvider()
    private let sleeper = ManualSleeper()
    private let clock = LockedValue(PollerFixture.now)

    private let alice = AccountID(host: "github.com", user: "alice")
    private let bob = AccountID(host: "github.com", user: "bob")

    /// alice と bob が最初の取得を終え、時計が 20 秒進んだ store。
    private func loadedStore() async -> NotificationStore {
        tokens.set("test-token-alice", for: alice)
        tokens.set("test-token-bob", for: bob)
        let client = GitHubAPIClient(transport: transport)
        let store = NotificationStore(
            makePoller: { [tokens, sleeper, clock] account, endpoints, _, _, _, onUpdate in
                AccountPoller(
                    accountID: account.id, endpoints: endpoints, client: client, tokens: tokens, sleep: sleeper.sleep,
                    now: { clock.value }, onUpdate: onUpdate)
            }, openURL: { _ in })
        store.sync(
            with: .accounts([
                AccountStatus(account: Account(id: alice, isActive: true), tokenState: .ready),
                AccountStatus(account: Account(id: bob, isActive: false), tokenState: .ready),
            ]))
        await sleeper.waitForSleeps(2)
        clock.withLock { $0 = $0.addingTimeInterval(20) }
        return store
    }

    @Test func fetchesEveryAccountNowAndShowsTheProgress() async {
        let store = await loadedStore()
        transport.pausedMethod.value = "GET"
        store.refresh()
        #expect(store.isRefreshing)
        await waitUntil { self.transport.requests.count == 4 }
        #expect(transport.ifModifiedSince == [nil, nil, nil, nil])
        #expect(store.isRefreshing)
        transport.pausedMethod.value = nil
        await waitUntil { MainActor.assumeIsolated { !store.isRefreshing } }
        #expect(!store.isRefreshing)
        store.stopAll()
    }

    @Test func keepsTheDiagnosticsOfAStoppedAccountWhenResuming() async {
        transport.setHandler { _ in PollerFixture.ok(1...1, scopes: "gist") }
        tokens.set("test-token-alice", for: alice)
        let client = GitHubAPIClient(transport: transport)
        let store = NotificationStore(
            makePoller: { [tokens, sleeper, clock] account, endpoints, _, _, _, onUpdate in
                AccountPoller(
                    accountID: account.id, endpoints: endpoints, client: client, tokens: tokens, sleep: sleeper.sleep,
                    now: { clock.value }, onUpdate: onUpdate)
            }, openURL: { _ in })
        store.sync(with: .accounts([AccountStatus(account: Account(id: alice, isActive: true), tokenState: .ready)]))
        await waitUntil { MainActor.assumeIsolated { store.feeds[alice]?.phase == .scopeInsufficient } }
        let stopped = store.feeds[alice]?.diagnostics
        #expect(stopped?.lastFetchedAt == nil)
        #expect(stopped?.scopes == OAuthScopes(header: "gist"))
        transport.pausedMethod.value = "GET"
        tokens.refreshedValue.value = "test-token-alice-2"
        store.refresh()
        // 再開したポーラーが出し直すまで、前の値を残す
        #expect(store.feeds[alice]?.phase == .loading)
        #expect(store.feeds[alice]?.diagnostics == stopped)
        transport.pausedMethod.value = nil
        store.stopAll()
    }

    @Test func endsTheProgressWhenAFetchFails() async {
        let store = await loadedStore()
        transport.setHandler { _ throws(TransportError) in
            throw .network(code: URLError.Code.notConnectedToInternet.rawValue)
        }
        store.refresh()
        await waitUntil { MainActor.assumeIsolated { !store.isRefreshing } }
        #expect(!store.isRefreshing)
        #expect(transport.requests.count == 4)
        store.stopAll()
    }

    @Test func ignoresAPressWhileRefreshing() async {
        let store = await loadedStore()
        transport.pausedMethod.value = "GET"
        store.refresh()
        await waitUntil { self.transport.requests.count == 4 }
        store.refresh()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(transport.requests.count == 4)
        transport.pausedMethod.value = nil
        await waitUntil { MainActor.assumeIsolated { !store.isRefreshing } }
        store.stopAll()
    }
}
