import Foundation
import Testing

@testable import Mewbell

/// `Last-Modified` より古いスレッドの増減を `304` が隠すので、定期的と再読み込みの後に条件なしで取り直す。
struct UnconditionalFetchTests {
    private let fixture: PollerFixture

    init() throws {
        fixture = try PollerFixture()
    }

    @Test func refetchesWithoutIfModifiedSinceEveryFiveMinutes() async {
        fixture.respond([
            PollerFixture.ok(1...3), PollerFixture.notModified, PollerFixture.ok(1...2, lastModified: "LM-2"),
            PollerFixture.notModified,
        ])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(2)
        #expect(fixture.ifModifiedSince == [nil, "LM-1"])
        #expect(fixture.last?.threads.count == 3)

        // 最初の取得から 5 分
        fixture.advance(by: 240)
        await fixture.sleeper.waitForSleeps(3)
        #expect(fixture.ifModifiedSince == [nil, "LM-1", nil])
        #expect(fixture.last?.threads.map(\.id) == ["1", "2"])

        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(4)
        #expect(fixture.ifModifiedSince == [nil, "LM-1", nil, "LM-2"])
        fixture.poller.stop()
    }

    /// 条件なしにした取得（5 分たった、または既読にした後）が失敗したら、次の取得もまた条件なしにする。
    @Test(arguments: [false, true])
    func retriesWithoutIfModifiedSinceAfterAFailedUnconditionalFetch(requested: Bool) async {
        fixture.route(gets: [PollerFixture.ok(1...1), HTTPResponse(statusCode: 500), PollerFixture.notModified])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        if requested {
            await fixture.poller.perform([.read(threadID: "1")])
        }
        fixture.advance(by: requested ? 60 : 300)
        await fixture.sleeper.waitForSleeps(2)
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(3)
        #expect(fixture.ifModifiedSince == [nil, nil, nil])
        fixture.poller.stop()
    }

    /// 条件付きの 200 は差分なので、条件なしで取り直す 5 分の起点にしない。
    @Test func doesNotCountAConditional200AsAFullFetch() async {
        fixture.respond([
            PollerFixture.ok(1...1), PollerFixture.ok(2...2, lastModified: "LM-2"), PollerFixture.ok(2...2),
        ])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        fixture.advance(by: 240)
        await fixture.sleeper.waitForSleeps(2)
        #expect(fixture.lastIDs == ["2", "1"])
        // 最初の取得（条件なし）から 5 分を過ぎたので、条件なしで取り直す
        fixture.advance(by: 120)
        await fixture.sleeper.waitForSleeps(3)
        #expect(fixture.ifModifiedSince == [nil, "LM-1", nil])
        #expect(fixture.lastIDs == ["2"])
        fixture.poller.stop()
    }

    @Test func refetchesWithoutIfModifiedSinceWhenTheClockGoesBack() async {
        fixture.respond([PollerFixture.ok(1...1), PollerFixture.notModified])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        fixture.advance(by: -3600)
        await fixture.sleeper.waitForSleeps(2)
        #expect(fixture.ifModifiedSince == [nil, nil])
        fixture.poller.stop()
    }
}
