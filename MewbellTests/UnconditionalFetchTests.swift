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

    /// 条件なしにした取得（5 分たった、または再読み込み）が失敗したら、次の取得もまた条件なしにする。
    @Test(arguments: [false, true])
    func retriesWithoutIfModifiedSinceAfterAFailedUnconditionalFetch(requested: Bool) async {
        fixture.respond([PollerFixture.ok(1...1), HTTPResponse(statusCode: 500), PollerFixture.notModified])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        if requested {
            fixture.poller.requestUnconditionalFetch()
        }
        fixture.advance(by: requested ? 60 : 300)
        await fixture.sleeper.waitForSleeps(2)
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(3)
        #expect(fixture.ifModifiedSince == [nil, nil, nil])
        fixture.poller.stop()
    }

    @Test func requestedFetchIsUnconditionalButNotEarlier() async {
        fixture.respond([
            PollerFixture.ok(1...1), PollerFixture.ok(1...2, lastModified: "LM-2"), PollerFixture.notModified,
        ])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        fixture.poller.requestUnconditionalFetch()
        try? await Task.sleep(for: .milliseconds(50))
        // 取得は早まらない（待ちも増えない）
        #expect(fixture.transport.requests.count == 1)
        #expect(fixture.sleeper.durations.count == 1)

        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(2)
        #expect(fixture.ifModifiedSince == [nil, nil])
        #expect(fixture.last?.threads.count == 2)

        // 取り終えたら、その次はまた条件付きに戻る
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(3)
        #expect(fixture.ifModifiedSince == [nil, nil, "LM-2"])
        #expect(fixture.sleeper.durations == [60, 60, 60].map { .seconds($0) })
        fixture.poller.stop()
    }

    @Test func countsAConditional200AsAFullFetch() async {
        fixture.respond([
            PollerFixture.ok(1...1), PollerFixture.ok(1...2, lastModified: "LM-2"), PollerFixture.notModified,
        ])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        fixture.advance(by: 240)
        await fixture.sleeper.waitForSleeps(2)
        // 条件付きの 200 から 5 分たっていないので、最初の取得から 5 分を過ぎても条件付きのまま
        fixture.advance(by: 120)
        await fixture.sleeper.waitForSleeps(3)
        #expect(fixture.ifModifiedSince == [nil, "LM-1", "LM-2"])
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
