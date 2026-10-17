import Foundation
import Testing

@testable import Mewbell

/// `AccountPoller.perform` に複数のスレッドを渡したとき（リポジトリのグループの既読・Done）のテスト。
struct GroupActionPollingTests {
    private let fixture: PollerFixture

    init() throws {
        fixture = try PollerFixture()
    }

    private func requests(_ method: String) -> [URLRequest] { fixture.requests(method) }
    private var lastIDs: [String] { fixture.lastIDs }
    private var now: Date { fixture.clock.value }

    /// 最初の取得を終えて待ち始めるまで進める。
    private func startAndLoad() async {
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
    }

    /// このスレッドへのリクエストか
    private static func isThread(_ id: String) -> @Sendable (URLRequest) -> Bool {
        { $0.url?.path.hasSuffix("/notifications/threads/\(id)") == true }
    }

    @Test func sendsTheRequestsOneAtATimeAndFetchesUnconditionallyInBetween() async {
        fixture.route(gets: [PollerFixture.ok(1...4), PollerFixture.ok(3...4)])
        await startAndLoad()
        fixture.transport.pausedWhere.value = Self.isThread("1")
        let done = Task { await fixture.poller.perform([.done(threadID: "1"), .done(threadID: "2")]) }
        await waitUntil { self.requests("DELETE").count == 1 }
        // どれもすぐに一覧から外し、1 件目の結果が出るまで 2 件目は送らない
        #expect(lastIDs == ["3", "4"])
        fixture.transport.pausedWhere.value = Self.isThread("2")
        await waitUntil { self.requests("DELETE").count == 2 }
        // 1 件目の結果が出た後に始まった取得は、2 件目を送っている間でも条件なし
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(2)
        #expect(fixture.ifModifiedSince == [nil, nil])
        fixture.transport.pausedWhere.value = nil
        await done.value
        #expect(requests("DELETE").map { $0.url?.lastPathComponent } == ["1", "2"])
        fixture.poller.stop()
    }

    @Test(arguments: [
        (HTTPResponse(statusCode: 401), FailureKind.unauthorized),
        (HTTPResponse(statusCode: 403, headers: ["X-RateLimit-Remaining": "0"]), FailureKind.rateLimited),
    ])
    func stopsSendingAfterAnAuthErrorOrARateLimit(response: HTTPResponse, kind: FailureKind) async {
        fixture.route(gets: [PollerFixture.ok(1...4), PollerFixture.ok(1...4)], ["DELETE": response])
        await startAndLoad()
        await fixture.poller.perform([.done(threadID: "1"), .done(threadID: "2"), .done(threadID: "3")])
        #expect(requests("DELETE").count == 1)
        // 送らないスレッドの前では待たない
        #expect(fixture.spacings.value.isEmpty)
        #expect(fixture.last?.actionFailure == ActionFailure(action: .done, kind: kind, occurredAt: now))
        #expect(lastIDs == ["4"])
        // 送らなかったスレッドも、その後に送った取得の結果で一覧に戻る
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(2)
        #expect(lastIDs == ["1", "2", "3", "4"])
        fixture.poller.stop()
    }

    @Test func keepsSendingAfterOtherFailuresAndKeepsOneNotice() async {
        fixture.respond(gets: [PollerFixture.ok(1...4)]) { request in
            Self.isThread("3")(request) ? HTTPResponse(statusCode: 205) : HTTPResponse(statusCode: 500)
        }
        await startAndLoad()
        await fixture.poller.perform([.read(threadID: "1"), .read(threadID: "2"), .read(threadID: "3")])
        #expect(requests("PATCH").count == 3)
        // 前の結果が失敗でも、2 件目と 3 件目の前に 1 秒ずつ空ける
        #expect(fixture.spacings.value == [.seconds(1), .seconds(1)])
        #expect(fixture.last?.actionFailure == ActionFailure(action: .read, kind: .httpStatus(500), occurredAt: now))
        fixture.poller.stop()
    }

    @Test func sendsNothingWithoutAToken() async {
        fixture.route(gets: [PollerFixture.ok(1...3), PollerFixture.ok(1...3)])
        await startAndLoad()
        await fixture.tokens.discardToken(for: PollerFixture.alice)
        await fixture.poller.perform([.read(threadID: "1"), .read(threadID: "2")])
        #expect(requests("PATCH").isEmpty)
        #expect(fixture.last?.actionFailure == ActionFailure(action: .read, kind: .noToken, occurredAt: now))
        #expect(lastIDs == ["3"])
        fixture.poller.stop()
    }

    @Test func stopsSendingWhenThePollerIsStoppedMidway() async {
        fixture.route(gets: [PollerFixture.ok(1...4)], ["DELETE": HTTPResponse(statusCode: 500)])
        await startAndLoad()
        fixture.transport.pausedWhere.value = Self.isThread("1")
        let done = Task {
            await fixture.poller.perform([.done(threadID: "1"), .done(threadID: "2"), .done(threadID: "3")])
        }
        await waitUntil { self.requests("DELETE").count == 1 }
        // アカウントの無効化・削除・終了で止めたら、残りは送らず、止まる前の失敗も知らせない
        fixture.poller.stop()
        fixture.transport.pausedWhere.value = nil
        await done.value
        #expect(requests("DELETE").count == 1)
        #expect(fixture.last?.actionFailure == nil)
        #expect(fixture.last?.diagnostics.lastActionFailure == nil)
    }

    @Test func stopsSendingWhenTheTokenIsDiscardedMidway() async {
        fixture.route(gets: [PollerFixture.ok(1...4)])
        await startAndLoad()
        fixture.transport.pausedWhere.value = Self.isThread("1")
        let done = Task {
            await fixture.poller.perform([.done(threadID: "1"), .done(threadID: "2"), .done(threadID: "3")])
        }
        await waitUntil { self.requests("DELETE").count == 1 }
        // 送っている間に捨てたトークンで、残りを送らない
        await fixture.tokens.discardToken(for: PollerFixture.alice)
        fixture.transport.pausedWhere.value = nil
        await done.value
        #expect(requests("DELETE").count == 1)
        #expect(fixture.last?.actionFailure == ActionFailure(action: .done, kind: .noToken, occurredAt: now))
        fixture.poller.stop()
    }

    @Test func showsAThreadThatArrivesWhileTheRequestsAreInFlight() async {
        fixture.route(gets: [PollerFixture.ok(1...2), PollerFixture.ok(1...3)])
        await startAndLoad()
        fixture.transport.pausedMethod.value = "DELETE"
        let done = Task { await fixture.poller.perform([.done(threadID: "1"), .done(threadID: "2")]) }
        await waitUntil { self.requests("DELETE").count == 1 }
        #expect(lastIDs.isEmpty)
        // 送っている間の取得で届いた同じリポジトリの 3 は出し、操作したスレッドは出さない
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(2)
        #expect(lastIDs == ["3"])
        fixture.transport.pausedMethod.value = nil
        await done.value
        #expect(requests("DELETE").map { $0.url?.lastPathComponent } == ["1", "2"])
        fixture.poller.stop()
    }

    @Test func waitsOneSecondAfterEachResultBeforeTheNextRequest() async throws {
        let spacer = ManualSleeper()
        let fixture = try PollerFixture(actionSpacing: spacer.sleep)
        fixture.route(gets: [PollerFixture.ok(1...4)])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        let done = Task {
            await fixture.poller.perform([.done(threadID: "1"), .done(threadID: "2"), .done(threadID: "3")])
        }
        // 1 件目は待たずに送り、その結果が出てから 1 秒待つまで 2 件目は送らない
        await spacer.waitForSleeps(1)
        #expect(fixture.requests("DELETE").count == 1)
        spacer.advance()
        await spacer.waitForSleeps(2)
        #expect(fixture.requests("DELETE").count == 2)
        spacer.advance()
        await done.value
        #expect(fixture.requests("DELETE").map { $0.url?.lastPathComponent } == ["1", "2", "3"])
        #expect(spacer.durations == [.seconds(1), .seconds(1)])
        fixture.poller.stop()
    }

    @Test func doesNotWaitForASingleThread() async {
        fixture.route(gets: [PollerFixture.ok(1...2)])
        await startAndLoad()
        await fixture.poller.perform([.read(threadID: "1")])
        #expect(requests("PATCH").count == 1)
        #expect(fixture.spacings.value.isEmpty)
        fixture.poller.stop()
    }

    @Test func sendsNoMoreAfterTheWaitWhenThePollerIsStoppedDuringIt() async throws {
        let spacer = ManualSleeper()
        let fixture = try PollerFixture(actionSpacing: spacer.sleep)
        fixture.route(gets: [PollerFixture.ok(1...4)], ["DELETE": HTTPResponse(statusCode: 500)])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        let done = Task { await fixture.poller.perform([.done(threadID: "1"), .done(threadID: "2")]) }
        await spacer.waitForSleeps(1)
        // 待っている間に止めたら、待ちが明けても残りは送らず、止まる前の失敗も知らせない
        fixture.poller.stop()
        spacer.advance()
        await done.value
        #expect(fixture.requests("DELETE").count == 1)
        #expect(fixture.last?.actionFailure == nil)
    }

    @Test func sendsNoMoreAfterTheWaitWhenTheTokenIsDiscardedDuringIt() async throws {
        let spacer = ManualSleeper()
        let fixture = try PollerFixture(actionSpacing: spacer.sleep)
        fixture.route(gets: [PollerFixture.ok(1...4)])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        let done = Task { await fixture.poller.perform([.done(threadID: "1"), .done(threadID: "2")]) }
        await spacer.waitForSleeps(1)
        // 待つ前に読んだトークンで、待った後に送らない
        await fixture.tokens.discardToken(for: PollerFixture.alice)
        spacer.advance()
        await done.value
        #expect(fixture.requests("DELETE").count == 1)
        #expect(
            fixture.last?.actionFailure
                == ActionFailure(action: .done, kind: .noToken, occurredAt: fixture.clock.value))
        fixture.poller.stop()
    }
}
