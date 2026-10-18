import Foundation
import Testing

@testable import Mewbell

/// `AccountPoller` のスレッドの件名の状態とイベントの取得（polling「スレッドのイベントの取得」）。
struct ThreadDetailsPollingTests {
    static let commented = ThreadDetails(state: .open, event: ThreadEvent(kind: .commented, actor: "bob"))

    /// 番号を持つ（状態とイベントを取る）スレッドの一覧。`updatedAt` は秒（12:00:SS）。
    static func list(_ items: [(id: Int, second: Int)]) -> HTTPResponse {
        let json = items.map { item in
            FakeHTTPTransport.threadJSON(
                id: String(item.id), updatedAt: String(format: "2026-10-08T12:00:%02dZ", item.second),
                subjectURL: "https://api.github.com/repos/octo/app/issues/\(item.id)")
        }
        return PollerFixture.ok(body: Data("[\(json.joined(separator: ","))]".utf8))
    }

    static func list(_ ids: [Int]) -> HTTPResponse {
        list(ids.map { ($0, 0) })
    }

    /// 件名の状態とイベントの取得か、Release のタグの取得か、run の検索か。
    static func isDetails(_ request: URLRequest) -> Bool {
        let path = request.url?.path() ?? ""
        return path.contains("/issues/") || path.contains("/releases/") || path.contains("/actions/runs")
    }

    /// Issue は 10:00 に作られ、12:00 に `bob` がコメントした。
    static func details(_ request: URLRequest) -> HTTPResponse {
        guard request.url?.path().hasSuffix("/timeline") == true else {
            return HTTPResponse(statusCode: 200, body: TimelineJSON.issue(createdAt: "2026-10-08T10:00:00Z"))
        }
        return HTTPResponse(
            statusCode: 200, body: TimelineJSON.page([TimelineJSON.commented(at: "2026-10-08T12:00:00Z", by: "bob")]))
    }

    /// 通知の取得には `notifications` を順に返し（尽きたら通信の失敗）、状態とイベントの取得には `details` を返す。
    /// 操作（`PATCH` など）には `205` を返す。
    func respond(
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

    func detailsRequests(_ fixture: PollerFixture) -> [URLRequest] {
        fixture.transport.requests.filter(Self.isDetails)
    }

    /// `id` を初めて含んだ一覧。
    func firstUpdate(containing id: String, _ fixture: PollerFixture) -> FeedState? {
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

    /// 条件付きの 200 に入っていなかったスレッドは一覧に残るので、状態とイベントも外さず、取り直さない。
    @Test func keepsTheDetailsOfThreadsMissingFromAConditional200() async throws {
        let fixture = try PollerFixture()
        respond(fixture, notifications: [Self.list([1]), Self.list([(2, 5)])])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(2)
        let notifications = fixture.transport.requests.filter { !Self.isDetails($0) }
        #expect(notifications.last?.value(forHTTPHeaderField: "If-Modified-Since") == "LM-1")
        #expect(fixture.lastIDs == ["2", "1"])
        #expect(fixture.last?.threads.allSatisfy { $0.details == Self.commented } == true)
        #expect(detailsRequests(fixture).count == 4)
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
        await fixture.poller.perform([.read(threadID: "1")])
        #expect(fixture.lastIDs == ["2"])
        fixture.transport.pausedWhere.value = nil
        await fixture.sleeper.waitForSleeps(1)
        #expect(fixture.lastIDs == ["2"])
        #expect(fixture.last?.threads.first?.details == Self.commented)
        fixture.poller.stop()
    }

    /// 条件付きの 200 に、既読にしたスレッドが入っているときも入っていないとき（今の一覧から重ねるとき）も戻さない。
    @Test(arguments: [false, true])
    func doesNotBringBackThreadsReadWhilePrefetching(fetchedAgain: Bool) async throws {
        let fixture = try PollerFixture()
        respond(fixture, notifications: [Self.list([1]), Self.list(fetchedAgain ? [1, 2] : [2])])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        fixture.transport.pausedWhere.value = { Self.isDetails($0) }
        fixture.advance(by: 60)
        await waitUntil { detailsRequests(fixture).count >= 3 }
        await fixture.poller.perform([.done(threadID: "1")])
        fixture.transport.pausedWhere.value = nil
        await fixture.sleeper.waitForSleeps(2)
        #expect(fixture.lastIDs == ["2"])
        #expect(
            !fixture.updates.value.contains { state in
                state.threads.map(\.id) == ["1", "2"] || state.threads.map(\.id) == ["2", "1"]
            })
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
}
