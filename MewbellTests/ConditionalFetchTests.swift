import Foundation
import Testing

@testable import Mewbell

/// `If-Modified-Since` を付けた取得の `200` は、その時刻より後に更新されたスレッドだけなので、今の一覧に重ねる。
struct ConditionalFetchTests {
    private let fixture: PollerFixture

    init() throws {
        fixture = try PollerFixture()
    }

    /// `items` のスレッドの一覧（`updatedAt` は 2026-10-08 12:MM:00 で、`minute` が MM）。
    private static func list(_ items: [(id: Int, minute: Int)], lastModified: String) -> HTTPResponse {
        let json = items.map { item in
            FakeHTTPTransport.threadJSON(
                id: String(item.id), updatedAt: String(format: "2026-10-08T12:%02d:00Z", item.minute))
        }
        return PollerFixture.ok(body: Data("[\(json.joined(separator: ","))]".utf8), lastModified: lastModified)
    }

    private static let unconditional = list([(3, 2), (2, 1), (1, 0)], lastModified: "LM-1")

    @Test func mergesTheThreadsIntoTheCurrentList() async throws {
        fixture.respond([
            Self.unconditional, Self.list([(4, 6), (2, 5)], lastModified: "LM-2"), PollerFixture.notModified,
        ])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(2)
        #expect(fixture.ifModifiedSince == [nil, "LM-1"])
        #expect(fixture.lastIDs == ["4", "2", "3", "1"])
        let replaced = try #require(fixture.last?.threads.first { $0.id == "2" })
        #expect(replaced.updatedAt == ISO8601DateFormatter().date(from: "2026-10-08T12:05:00Z"))
        // 次の条件付きの取得には、重ねた 200 の `Last-Modified` を付ける
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(3)
        #expect(fixture.ifModifiedSince == [nil, "LM-1", "LM-2"])
        #expect(fixture.lastIDs == ["4", "2", "3", "1"])
        fixture.poller.stop()
    }

    /// 既読化のリクエストが終わっていない間の条件付きの 200 で、既読にしたスレッドを戻さない。
    @Test func keepsAThreadBeingReadOutOfTheMergedList() async {
        fixture.route(gets: [Self.unconditional, Self.list([(4, 6), (2, 5)], lastModified: "LM-2")])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        fixture.transport.pausedMethod.value = "PATCH"
        let read = Task { await fixture.poller.perform([.read(threadID: "2")]) }
        await waitUntil { fixture.requests("PATCH").count == 1 }
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(2)
        #expect(fixture.ifModifiedSince == [nil, "LM-1"])
        #expect(fixture.lastIDs == ["4", "3", "1"])
        fixture.transport.pausedMethod.value = nil
        await read.value
        fixture.poller.stop()
    }
}
