import Foundation
import Testing

@testable import Mewbell

/// `AccountPoller` が記録する打ち切り・間隔・スコープ・取得の失敗のテスト。
struct PollingDiagnosticsTests {
    private let fixture: PollerFixture

    init() throws {
        fixture = try PollerFixture()
    }

    private var now: Date { fixture.clock.value }

    /// 10 ページすべてに `rel="next"` がある 1 回の取得の応答。
    private static func truncatedPages() -> [HTTPResponse] {
        (1...10).map { page in
            HTTPResponse(
                statusCode: 200,
                headers: [
                    "Last-Modified": "LM-1", "X-OAuth-Scopes": "repo", "X-Poll-Interval": "60",
                    "Link": "<https://api.github.com/notifications?page=\(page + 1)>; rel=\"next\"",
                ],
                body: FakeHTTPTransport.page((page * 100)...(page * 100)))
        }
    }

    private static func ok(pollInterval: String?, scopes: String = "repo") -> HTTPResponse {
        var headers = ["Last-Modified": "LM-1", "X-OAuth-Scopes": scopes]
        headers["X-Poll-Interval"] = pollInterval
        return HTTPResponse(statusCode: 200, headers: headers, body: FakeHTTPTransport.page(1...1))
    }

    @Test func keepsTheTruncationAcrossANotModifiedAndClearsItWhenTheListEnds() async {
        fixture.respond(Self.truncatedPages() + [PollerFixture.notModified, PollerFixture.ok(1...3)])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        #expect(fixture.last?.isTruncated == true)
        #expect(fixture.last?.threads.count == 10)
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(2)
        #expect(fixture.ifModifiedSince.last == "LM-1")
        #expect(fixture.last?.isTruncated == true)
        fixture.advance(by: 300)
        await fixture.sleeper.waitForSleeps(3)
        #expect(fixture.last?.isTruncated == false)
        fixture.poller.stop()
    }

    /// 条件付きの 200 の一覧の残りは前の取得のものなので、打ち切られなかった条件付きの 200 では打ち切りを保つ。
    @Test func keepsTheTruncationAcrossAConditional200() async {
        fixture.respond(Self.truncatedPages() + [PollerFixture.ok(1...1, lastModified: "LM-2")])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(2)
        #expect(fixture.ifModifiedSince.last == "LM-1")
        #expect(fixture.last?.threads.count == 11)
        #expect(fixture.last?.isTruncated == true)
        fixture.poller.stop()
    }

    /// 間隔の境界の値は `FeedDiagnosticsTests.derivesThePollInterval` で確かめる。
    @Test func recordsTheIntervalAndTheNextFetch() async {
        fixture.respond([Self.ok(pollInterval: "120")])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        #expect(fixture.last?.diagnostics.pollInterval == PollIntervalInfo(seconds: 120, fromHeader: true))
        #expect(fixture.last?.diagnostics.nextFetchAt == now.addingTimeInterval(120))
        fixture.poller.stop()
    }

    @Test func recordsTheScopesAndDropsThemWhenTheTokenIsRefreshed() async {
        // 2 回目の取得が 401 で、取り直せない
        fixture.respond([Self.ok(pollInterval: "60", scopes: "repo, read:org"), HTTPResponse(statusCode: 401)])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        #expect(fixture.last?.diagnostics.scopes == OAuthScopes(header: "repo, read:org"))
        fixture.advance(by: 60)
        await waitUntil { self.fixture.last?.phase == .unauthorized }
        #expect(fixture.last?.diagnostics.scopes == nil)
        #expect(fixture.last?.diagnostics.lastFetchFailure?.kind == .unauthorized)
    }

    @Test func keepsTheLastFetchFailureAfterASuccess() async {
        fixture.respond([HTTPResponse(statusCode: 502), PollerFixture.ok(1...2)])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        let failedAt = now
        #expect(
            fixture.last?.diagnostics.lastFetchFailure == TimedFailure(kind: .httpStatus(502), occurredAt: failedAt))
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(2)
        #expect(fixture.last?.phase == .loaded(updatedAt: now))
        #expect(fixture.last?.diagnostics.lastFetchedAt == now)
        #expect(
            fixture.last?.diagnostics.lastFetchFailure == TimedFailure(kind: .httpStatus(502), occurredAt: failedAt))
        fixture.poller.stop()
    }

    @Test func clearsTheScheduleWhenStoppedButKeepsTheLastFailure() async {
        fixture.respond([HTTPResponse(statusCode: 502), PollerFixture.ok(1...2, scopes: "gist")])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        #expect(fixture.last?.diagnostics.nextFetchAt != nil)
        fixture.advance(by: 60)
        await waitUntil { self.fixture.last?.phase == .scopeInsufficient }
        let last = fixture.last
        #expect(last?.diagnostics.nextFetchAt == nil)
        #expect(last?.diagnostics.lastFetchFailure?.kind == .httpStatus(502))
        #expect(last?.diagnostics.scopes == OAuthScopes(header: "gist"))
    }
}

/// 最初の取得の前の、次の取得の予定時刻のテスト。
struct NextFetchDiagnosticsTests {
    private let fixture: PollerFixture

    init() throws {
        fixture = try PollerFixture()
    }

    @Test func announcesACarriedWaitBeforeTheFirstFetch() async throws {
        let until = PollerFixture.now.addingTimeInterval(30)
        let updates = LockedValue<[FeedState]>([])
        let sleeper = ManualSleeper()
        let poller = AccountPoller(
            accountID: PollerFixture.alice, endpoints: try #require(APIEndpoints(host: "github.com")),
            client: GitHubAPIClient(transport: fixture.transport), tokens: fixture.tokens,
            carriedWait: CarriedWait(until: until, rateLimited: false, lastAttemptStartedAt: nil),
            sleep: sleeper.sleep, now: { PollerFixture.now },
            onUpdate: { state in updates.withLock { $0.append(state) } })
        poller.start()
        await sleeper.waitForSleeps(1)
        #expect(updates.value.last?.diagnostics.nextFetchAt == until)
        #expect(fixture.transport.requests.isEmpty)
        poller.stop()
    }
}

/// `AccountPoller` が記録する操作の失敗のテスト。
struct ActionFailurePollingTests {
    private let fixture: PollerFixture

    init() throws {
        fixture = try PollerFixture()
    }

    private var now: Date { fixture.clock.value }

    /// 最初の取得を終えて待ち始めるまで進める。
    private func startAndLoad() async {
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
    }

    @Test func recordsAFailedReadWithoutChangingTheFetchState() async {
        fixture.route(gets: [PollerFixture.ok(1...3)], ["PATCH": HTTPResponse(statusCode: 500)])
        await startAndLoad()
        let before = fixture.last
        await fixture.poller.perform(.read(threadID: "2"))
        let expected = ActionFailure(action: .read, kind: .httpStatus(500), occurredAt: now)
        #expect(fixture.last?.actionFailure == expected)
        #expect(fixture.last?.diagnostics.lastActionFailure == expected)
        #expect(fixture.last?.phase == before?.phase)
        #expect(fixture.last?.diagnostics.nextFetchAt == before?.diagnostics.nextFetchAt)
        fixture.poller.stop()
    }

    @Test func keepsTheNoticeWhenAFetchSentBeforeTheFailureEnds() async {
        fixture.route(
            gets: [PollerFixture.ok(1...3), PollerFixture.ok(1...3), PollerFixture.ok(1...3)],
            ["DELETE": HTTPResponse(statusCode: 401)])
        await startAndLoad()
        fixture.transport.pausedMethod.value = "GET"
        fixture.advance(by: 60)
        await waitUntil { self.fixture.requests("GET").count == 2 }
        await fixture.poller.perform(.done(threadID: "2"))
        #expect(fixture.last?.actionFailure?.kind == .unauthorized)
        // Done の前に送った取得が終わっても消さない
        fixture.transport.pausedMethod.value = nil
        await fixture.sleeper.waitForSleeps(2)
        #expect(fixture.last?.actionFailure == ActionFailure(action: .done, kind: .unauthorized, occurredAt: now))
        // Done の後に送った取得の成功で消す。Diagnostics には残す
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(3)
        #expect(fixture.last?.actionFailure == nil)
        #expect(fixture.last?.diagnostics.lastActionFailure?.action == .done)
        fixture.poller.stop()
    }

    @Test func recordsARateLimitedMarkAllRead() async {
        fixture.route(
            gets: [PollerFixture.ok(1...3)],
            ["PUT": HTTPResponse(statusCode: 403, headers: ["X-RateLimit-Remaining": "0"])])
        await startAndLoad()
        await fixture.poller.markAllRead(through: now)
        #expect(fixture.last?.actionFailure == ActionFailure(action: .markAllRead, kind: .rateLimited, occurredAt: now))
        fixture.poller.stop()
    }

    @Test func recordsAReadThatWasNotSentForLackOfAToken() async {
        fixture.route(gets: [PollerFixture.ok(1...3)])
        await startAndLoad()
        await fixture.tokens.discardToken(for: PollerFixture.alice)
        await fixture.poller.perform(.read(threadID: "2"))
        #expect(fixture.requests("PATCH").isEmpty)
        #expect(fixture.last?.actionFailure?.kind == .noToken)
        fixture.poller.stop()
    }

    @Test func neitherSendsNorRecordsWhileStopped() async {
        fixture.route(gets: [PollerFixture.ok(1...3, scopes: "gist")], [:])
        fixture.poller.start()
        await waitUntil { self.fixture.last?.phase == .scopeInsufficient }
        await fixture.poller.perform(.read(threadID: "2"))
        await fixture.poller.perform(.done(threadID: "2"))
        await fixture.poller.markAllRead(through: now)
        #expect(fixture.transport.requests.allSatisfy { $0.httpMethod == "GET" })
        #expect(fixture.last?.actionFailure == nil)
        #expect(fixture.last?.diagnostics.lastActionFailure == nil)
    }

    @Test func doesNotRecordSuccesses() async {
        fixture.route(gets: [PollerFixture.ok(1...3)])
        await startAndLoad()
        await fixture.poller.perform(.read(threadID: "1"))
        await fixture.poller.perform(.done(threadID: "2"))
        await fixture.poller.markAllRead(through: now)
        #expect(fixture.last?.actionFailure == nil)
        #expect(fixture.last?.diagnostics.lastActionFailure == nil)
        fixture.poller.stop()
    }

    @Test func clearsTheNoticeWhenStopped() async {
        // 既読化の失敗の後の取得が 401 で、トークンを取り直せない
        fixture.route(
            gets: [PollerFixture.ok(1...3), HTTPResponse(statusCode: 401)], ["PATCH": HTTPResponse(statusCode: 500)])
        await startAndLoad()
        await fixture.poller.perform(.read(threadID: "2"))
        fixture.advance(by: 60)
        await waitUntil { self.fixture.last?.phase == .unauthorized }
        #expect(fixture.last?.actionFailure == nil)
        #expect(fixture.last?.diagnostics.lastActionFailure?.action == .read)
    }
}
