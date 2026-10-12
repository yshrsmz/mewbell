import Foundation
import Testing

@testable import Mewbell

// 隠しているスレッド・トークン・失敗の扱い
extension ThreadDetailsPollingTests {
    @Test func sendsNothingWithoutAToken() async throws {
        let fixture = try PollerFixture()
        let tokens = FirstCallTokens()
        let updates = LockedValue<[FeedState]>([])
        let poller = AccountPoller(
            accountID: PollerFixture.alice, endpoints: try #require(APIEndpoints(host: "github.com")),
            client: GitHubAPIClient(transport: fixture.transport), tokens: tokens, sleep: fixture.sleeper.sleep,
            onUpdate: { state in updates.withLock { $0.append(state) } })
        respond(fixture, notifications: [Self.list([1])])
        poller.start()
        await fixture.sleeper.waitForSleeps(1)
        #expect(updates.value.last?.threads.count == 1)
        #expect(detailsRequests(fixture).isEmpty)
        poller.stop()
    }
    @Test func skipsHiddenThreads() async throws {
        let fixture = try PollerFixture()
        let both = Self.list([(1, 0), (2, 30)])
        respond(fixture, notifications: [Self.list([1]), Self.list([1]), both, both])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        let newest = try #require(fixture.last?.threads.first?.updatedAt)
        await fixture.poller.markAllRead(through: newest)
        for cycle in 2...4 {
            fixture.advance(by: 60)
            await fixture.sleeper.waitForSleeps(cycle)
        }
        // すべて既読で隠している 1 は、一覧に出さず、状態とイベントも取り直さない
        #expect(fixture.lastIDs == ["2"])
        #expect(detailsRequests(fixture).filter { $0.url?.path().contains("/issues/1") == true }.count == 2)
        fixture.poller.stop()
    }

    @Test func doesNotRetryAPrefetchFailureInTheSameCycle() async throws {
        let fixture = try PollerFixture()
        respond(fixture, notifications: [Self.list([1]), Self.list([1, 2])]) { request in
            request.url?.path().contains("/issues/2") == true ? HTTPResponse(statusCode: 502) : Self.details(request)
        }
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(2)
        #expect(detailsRequests(fixture).filter { $0.url?.path().contains("/issues/2") == true }.count == 1)
        fixture.poller.stop()
    }

    @Test func refreshDoesNotWaitForDetails() async throws {
        let fixture = try PollerFixture()
        respond(fixture, notifications: [Self.list([1, 2]), Self.list([1, 2])])
        fixture.transport.pausedWhere.value = { Self.isDetails($0) }
        fixture.poller.start()
        await waitUntil { detailsRequests(fixture).count >= 2 }
        let refreshed = Task { await fixture.poller.refreshNow() }
        // 取得の下限（前の取得の開始から 10 秒）までの待ちに入る
        await fixture.sleeper.waitForSleeps(1)
        fixture.advance(by: 10)
        await refreshed.value
        #expect(fixture.transport.requests.filter { !Self.isDetails($0) }.count == 2)
        fixture.transport.pausedWhere.value = nil
        fixture.poller.stop()
    }

    @Test func keepsDetailsOfThreadsHiddenForAWhile() async throws {
        let fixture = try PollerFixture()
        let queue = LockedValue([Self.list([1]), Self.list([1]), Self.list([1])])
        fixture.transport.setHandler { request throws(TransportError) in
            if request.httpMethod != "GET" { return HTTPResponse(statusCode: 500) }
            if Self.isDetails(request) { return Self.details(request) }
            guard let next = queue.withLock({ $0.isEmpty ? nil : $0.removeFirst() }) else {
                throw .network(code: URLError.Code.notConnectedToInternet.rawValue)
            }
            return next
        }
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        // 既読にするリクエストの途中の取得では 1 を隠し、既読にできずに 1 が一覧に戻る
        fixture.transport.pausedMethod.value = "PATCH"
        let read = Task { await fixture.poller.perform(.read(threadID: "1")) }
        await waitUntil { !fixture.requests("PATCH").isEmpty }
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(2)
        #expect(fixture.lastIDs.isEmpty)
        fixture.transport.pausedMethod.value = nil
        await read.value
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(3)
        #expect(fixture.lastIDs == ["1"])
        #expect(fixture.last?.threads.first?.details == Self.commented)
        #expect(detailsRequests(fixture).count == 2)
        fixture.poller.stop()
    }

    @Test func refreshInterruptsThePrefetch() async throws {
        let fixture = try PollerFixture()
        respond(fixture, notifications: [Self.list([1]), Self.list([1, 2]), Self.list([1, 2])])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        fixture.transport.pausedWhere.value = { Self.isDetails($0) }
        fixture.advance(by: 60)
        await waitUntil { detailsRequests(fixture).count >= 3 }
        let refreshed = Task { await fixture.poller.refreshNow() }
        await fixture.sleeper.waitForSleeps(2)
        // 新着の 2 は、止めた取得の分を付けずに知らせる
        #expect(firstUpdate(containing: "2", fixture)?.threads.first { $0.id == "2" }?.details == nil)
        fixture.advance(by: 10)
        await refreshed.value
        #expect(fixture.transport.requests.filter { !Self.isDetails($0) }.count == 3)
        fixture.transport.pausedWhere.value = nil
        fixture.poller.stop()
    }

    @Test func prefetchesNewThreadsOfARefreshedFetch() async throws {
        let fixture = try PollerFixture()
        respond(fixture, notifications: [Self.list([1]), Self.list([1, 2])])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        // 待っている間に再読み込みを押す。その取得で届いた新着の 2 は、状態とイベントを付けて知らせる
        fixture.moveClock(by: 60)
        await fixture.poller.refreshNow()
        let published = try #require(firstUpdate(containing: "2", fixture))
        #expect(published.threads.first { $0.id == "2" }?.details == Self.commented)
        fixture.poller.stop()
    }

    @Test func skipsDetailsWhileARefreshIsWaiting() async throws {
        let fixture = try PollerFixture()
        respond(fixture, notifications: [Self.list([1]), Self.list([1, 2]), Self.list([1, 2])])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        // 通知の取得の最中に再読み込みを押す
        fixture.transport.pausedWhere.value = { !Self.isDetails($0) }
        fixture.advance(by: 60)
        await waitUntil { fixture.transport.requests.filter { !Self.isDetails($0) }.count == 2 }
        let before = detailsRequests(fixture).count
        let refreshed = Task { await fixture.poller.refreshNow() }
        await fixture.waitForPendingRefresh()
        fixture.transport.pausedWhere.value = nil
        await fixture.sleeper.waitForSleeps(2)
        // 再読み込みを待っている間は、新着の 2 の分も取らない
        #expect(detailsRequests(fixture).count == before)
        fixture.advance(by: 10)
        await refreshed.value
        fixture.poller.stop()
    }
}

/// 最初の 1 回だけトークンを返す `TokenProviding`（通知を取った後にトークンが無くなったことにする）。
private final class FirstCallTokens: TokenProviding {
    private let calls = LockedValue(0)

    func currentToken(for id: AccountID) async -> AccessToken? {
        let call = calls.withLock { count -> Int in
            count += 1
            return count
        }
        return call == 1 ? AccessToken(ghOutput: Data("test-token-alice".utf8)) : nil
    }

    func refreshToken(for id: AccountID) async -> AccessToken? { nil }

    func discardToken(for id: AccountID) async {}
}
