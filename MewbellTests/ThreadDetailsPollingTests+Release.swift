import Foundation
import Testing

@testable import Mewbell

// Release のスレッドのタグの取得
extension ThreadDetailsPollingTests {
    static let tag = "rust-v1.0.0"
    static let tagged = ThreadDetails(state: nil, event: nil, resource: .release(tag: tag))

    /// リリースの ID を持つ Release のスレッドの一覧。
    static func releases(_ ids: [Int]) -> HTTPResponse {
        let json = ids.map { id in
            FakeHTTPTransport.threadJSON(
                id: String(id), subjectURL: "https://api.github.com/repos/octo/app/releases/\(id)", type: "Release")
        }
        return PollerFixture.ok(body: Data("[\(json.joined(separator: ","))]".utf8))
    }

    /// リリースの取得にはタグ `tag` を返す。
    static func release(_ request: URLRequest) -> HTTPResponse {
        HTTPResponse(statusCode: 200, body: Data(#"{"tag_name": "\#(tag)"}"#.utf8))
    }

    @Test func fetchesTheTagOfNewReleasesBeforePublishing() async throws {
        let fixture = try PollerFixture()
        respond(fixture, notifications: [Self.releases([1]), Self.releases([1, 2])], details: Self.release)
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(2)
        let first = try #require(firstUpdate(containing: "2", fixture))
        #expect(first.threads.first { $0.id == "2" }?.details == Self.tagged)
        let releaseRequests = detailsRequests(fixture)
        let releaseURLs = releaseRequests.compactMap { $0.url?.absoluteString }
        #expect(releaseURLs.contains("https://api.github.com/repos/octo/app/releases/2"))
        #expect(
            releaseRequests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer test-token-alice" })
        fixture.poller.stop()
    }

    @Test func tagsTheFirstListAfterPublishing() async throws {
        let fixture = try PollerFixture()
        respond(fixture, notifications: [Self.releases([1, 2])], details: Self.release)
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        let first = try #require(fixture.updates.value.first { $0.phase != .loading })
        #expect(first.threads.allSatisfy { $0.details == nil })
        #expect(fixture.last?.threads.allSatisfy { $0.details == Self.tagged } == true)
        #expect(detailsRequests(fixture).count == 2)
        fixture.poller.stop()
    }
}
