import Foundation
import Testing

@testable import Mewbell

/// `AccountPoller` のスレッドの件名の状態とイベントの取得（polling「スレッドのイベントの取得」）。
struct ThreadDetailsPollingTests {
    private static let commented = ThreadDetails(state: .open, event: ThreadEvent(kind: .commented, actor: "bob"))

    /// 番号を持つ（状態とイベントを取る）スレッドの一覧。`updatedAt` は秒（12:00:SS）。
    private static func list(_ items: [(id: Int, second: Int)]) -> HTTPResponse {
        let json = items.map { item in
            FakeHTTPTransport.threadJSON(
                id: String(item.id), updatedAt: String(format: "2026-10-08T12:00:%02dZ", item.second),
                subjectURL: "https://api.github.com/repos/octo/app/issues/\(item.id)")
        }
        return PollerFixture.ok(body: Data("[\(json.joined(separator: ","))]".utf8))
    }

    private static func list(_ ids: [Int]) -> HTTPResponse {
        list(ids.map { ($0, 0) })
    }

    private static func isDetails(_ request: URLRequest) -> Bool {
        request.url?.path().contains("/issues/") == true
    }

    /// Issue は 10:00 に作られ、12:00 に `bob` がコメントした。
    private static func details(_ request: URLRequest) -> HTTPResponse {
        guard request.url?.path().hasSuffix("/timeline") == true else {
            return HTTPResponse(statusCode: 200, body: TimelineJSON.issue(createdAt: "2026-10-08T10:00:00Z"))
        }
        return HTTPResponse(
            statusCode: 200, body: TimelineJSON.page([TimelineJSON.commented(at: "2026-10-08T12:00:00Z", by: "bob")]))
    }

    /// 通知の取得には `notifications` を順に返し（尽きたら通信の失敗）、状態とイベントの取得には `details` を返す。
    /// 操作（`PATCH` など）には `205` を返す。
    private func respond(
        _ fixture: PollerFixture, notifications: [HTTPResponse],
        details: @escaping @Sendable (URLRequest) -> HTTPResponse = details
    ) {
        let queue = LockedValue(notifications)
        fixture.transport.setHandler { request throws(TransportError) in
            if request.httpMethod != "GET" { return HTTPResponse(statusCode: 205) }
            if Self.isDetails(request) { return details(request) }
            guard let next = queue.withLock({ $0.isEmpty ? nil : $0.removeFirst() }) else {
                throw .network(code: URLError.Code.notConnectedToInternet.rawValue)
            }
            return next
        }
    }

    private func detailsRequests(_ fixture: PollerFixture) -> [URLRequest] {
        fixture.transport.requests.filter(Self.isDetails)
    }

    /// `id` を初めて含んだ一覧。
    private func firstUpdate(containing id: String, _ fixture: PollerFixture) -> FeedState? {
        fixture.updates.value.first { $0.threads.contains { $0.id == id } }
    }

    @Test func fetchesNewThreadsBeforePublishing() async throws {
        let fixture = try PollerFixture()
        respond(fixture, notifications: [Self.list([1]), Self.list([1, 2])])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(2)
        let first = try #require(firstUpdate(containing: "2", fixture))
        #expect(first.threads.first { $0.id == "2" }?.details == Self.commented)
        fixture.poller.stop()
    }

    @Test func publishesTheFirstListWithoutWaiting() async throws {
        let fixture = try PollerFixture()
        respond(fixture, notifications: [Self.list(Array(1...12))])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        let first = try #require(fixture.updates.value.first { $0.phase != .loading })
        #expect(first.threads.count == 12)
        #expect(first.threads.allSatisfy { $0.details == nil })
        #expect(fixture.last?.threads.count == 12)
        #expect(fixture.last?.threads.allSatisfy { $0.details == Self.commented } == true)
        #expect(detailsRequests(fixture).count == 24)
        fixture.poller.stop()
    }

    @Test func limitsTheThreadsFetchedBeforePublishing() async throws {
        let fixture = try PollerFixture()
        let new = (2...16).map { ($0, $0) }
        respond(fixture, notifications: [Self.list([(1, 0)]), Self.list([(1, 0)] + new)])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(2)
        let published = try #require(firstUpdate(containing: "2", fixture))
        let withDetails = published.threads.filter { $0.details != nil }.map(\.id)
        // 1 は最初の一覧の後に取ってある。新着は更新日時が新しい 10 件（7〜16）だけ
        #expect(Set(withDetails) == Set(["1"] + (7...16).map(String.init)))
        #expect(fixture.last?.threads.allSatisfy { $0.details != nil } == true)
        fixture.poller.stop()
    }

    @Test func doesNotRefetchUnchangedThreads() async throws {
        let fixture = try PollerFixture()
        respond(fixture, notifications: [Self.list([1]), Self.list([1])])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        #expect(detailsRequests(fixture).count == 2)
        fixture.advance(by: 300)
        await fixture.sleeper.waitForSleeps(2)
        #expect(detailsRequests(fixture).count == 2)
        #expect(fixture.last?.threads.first?.details == Self.commented)
        fixture.poller.stop()
    }

    @Test func refetchesWhenTheUpdateAdvances() async throws {
        let fixture = try PollerFixture()
        let halfPast = try #require(ThreadEventResolver.date("2026-10-08T12:30:00Z"))
        // 12:00:00 のコメントは 12:30 の更新の近さの幅に入らないので、取り直した後はイベントが付かない
        let later = PollerFixture.ok(
            body: Data(
                "[\(FakeHTTPTransport.threadJSON(id: "1", updatedAt: "2026-10-08T12:30:00Z", subjectURL: "https://api.github.com/repos/octo/app/issues/1"))]"
                    .utf8))
        respond(fixture, notifications: [Self.list([1]), later])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(2)
        #expect(detailsRequests(fixture).count == 4)
        // 12:30 の一覧は、取り直した結果を付けて初めて知らされる（12:00 のイベントは付けない）
        let updated = fixture.updates.value.filter { $0.threads.first?.updatedAt == halfPast }
        #expect(updated.first?.threads.first?.details == ThreadDetails(state: .open, event: nil))
        fixture.poller.stop()
    }

    @Test func failuresDoNotChangeTheFeedState() async throws {
        let fixture = try PollerFixture()
        respond(fixture, notifications: [Self.list([1]), Self.list([1])]) { _ in HTTPResponse(statusCode: 502) }
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        let state = try #require(fixture.last)
        #expect(state.phase == .loaded(updatedAt: PollerFixture.now))
        #expect(state.diagnostics.lastFetchFailure == nil)
        #expect(state.threads.first?.details == nil)
        #expect(detailsRequests(fixture).count == 1)
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(2)
        #expect(detailsRequests(fixture).count == 2)
        #expect(fixture.last?.diagnostics.lastFetchFailure == nil)
        #expect(fixture.sleeper.durations == [.seconds(60), .seconds(60)])
        fixture.poller.stop()
    }

    @Test func pausesOnRateLimits() async throws {
        let fixture = try PollerFixture()
        let reset = PollerFixture.now.addingTimeInterval(600)
        let limited = HTTPResponse(
            statusCode: 403,
            headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": String(Int(reset.timeIntervalSince1970))])
        respond(fixture, notifications: [Self.list([1, 2]), Self.list([1, 2]), Self.list([1, 2])]) { _ in limited }
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        // 1 件目でレート制限になり、残りは取らない（同時に始めた分は返る）
        let afterFirst = detailsRequests(fixture).count
        #expect(afterFirst <= 2)
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(2)
        #expect(detailsRequests(fixture).count == afterFirst)
        #expect(fixture.last?.phase == .loaded(updatedAt: PollerFixture.now.addingTimeInterval(60)))
        fixture.advance(by: 600)
        await fixture.sleeper.waitForSleeps(3)
        #expect(detailsRequests(fixture).count > afterFirst)
        fixture.poller.stop()
    }

    @Test func doesNotBringBackThreadsReadWhileFetching() async throws {
        let fixture = try PollerFixture()
        respond(fixture, notifications: [Self.list([1, 2])])
        fixture.transport.pausedWhere.value = { Self.isDetails($0) }
        fixture.poller.start()
        await waitUntil { fixture.updates.value.contains { $0.threads.count == 2 } }
        await waitUntil { detailsRequests(fixture).count >= 2 }
        await fixture.poller.perform(.read(threadID: "1"))
        #expect(fixture.lastIDs == ["2"])
        fixture.transport.pausedWhere.value = nil
        await fixture.sleeper.waitForSleeps(1)
        #expect(fixture.lastIDs == ["2"])
        #expect(fixture.last?.threads.first?.details == Self.commented)
        fixture.poller.stop()
    }

    @Test func doesNotBringBackThreadsReadWhilePrefetching() async throws {
        let fixture = try PollerFixture()
        respond(fixture, notifications: [Self.list([1]), Self.list([1, 2])])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        fixture.transport.pausedWhere.value = { Self.isDetails($0) }
        fixture.advance(by: 60)
        await waitUntil { detailsRequests(fixture).count >= 3 }
        await fixture.poller.perform(.done(threadID: "1"))
        fixture.transport.pausedWhere.value = nil
        await fixture.sleeper.waitForSleeps(2)
        #expect(fixture.lastIDs == ["2"])
        #expect(
            !fixture.updates.value.contains { state in
                state.threads.map(\.id) == ["1", "2"] || state.threads.map(\.id) == ["2", "1"]
            })
        fixture.poller.stop()
    }

    @Test func stopsWaitingAtTheTimeLimit() async throws {
        let fixture = try PollerFixture(detailsTimeout: .milliseconds(100))
        respond(fixture, notifications: [Self.list([1]), Self.list([1, 2])])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        fixture.transport.pausedWhere.value = { Self.isDetails($0) }
        fixture.advance(by: 60)
        await waitUntil { firstUpdate(containing: "2", fixture) != nil }
        let published = try #require(firstUpdate(containing: "2", fixture))
        #expect(published.threads.first { $0.id == "2" }?.details == nil)
        fixture.transport.pausedWhere.value = nil
        // 打ち切った分は一時的な失敗として扱い、同じ回には取り直さず、次の回に取る
        await fixture.sleeper.waitForSleeps(2)
        #expect(fixture.last?.threads.first { $0.id == "2" }?.details == nil)
        respond(fixture, notifications: [Self.list([1, 2])])
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(3)
        #expect(fixture.last?.threads.first { $0.id == "2" }?.details == Self.commented)
        fixture.poller.stop()
    }

    @Test func forgetsEverythingWhenStopped() async throws {
        let fixture = try PollerFixture()
        respond(
            fixture, notifications: [Self.list([1]), HTTPResponse(statusCode: 401), HTTPResponse(statusCode: 401)])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        fixture.tokens.refreshedValue.value = "test-token-alice-2"
        fixture.advance(by: 60)
        await waitUntil { fixture.last?.phase == .unauthorized }
        #expect(fixture.last?.threads.isEmpty == true)
        // 再開した後の最初の一覧は、取ってあったイベントを付けずに知らせ、取り直す
        respond(fixture, notifications: [Self.list([1])])
        let before = detailsRequests(fixture).count
        let stoppedAt = fixture.updates.value.count
        await fixture.poller.refreshNow()
        await fixture.sleeper.waitForSleeps(2)
        let resumed = try #require(fixture.updates.value.dropFirst(stoppedAt).first { !$0.threads.isEmpty })
        #expect(resumed.threads.first?.details == nil)
        #expect(detailsRequests(fixture).count == before + 2)
        #expect(fixture.last?.threads.first?.details == Self.commented)
        fixture.poller.stop()
    }

    @Test func sendsOnlyTheAccountsToken() async throws {
        let fixture = try PollerFixture()
        respond(fixture, notifications: [Self.list([1, 2])])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        let requests = detailsRequests(fixture)
        #expect(requests.count == 4)
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer test-token-alice" })
        fixture.poller.stop()
    }
}

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
