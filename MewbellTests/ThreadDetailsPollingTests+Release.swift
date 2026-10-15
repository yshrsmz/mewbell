import Foundation
import Testing

@testable import Mewbell

// Release のスレッドのタグの取得
extension ThreadDetailsPollingTests {
    static let tagged = ThreadDetails(state: nil, event: nil, releaseTag: "rust-v1.0.0")

    /// リリースの ID を持つ Release のスレッドの一覧。
    static func releases(_ ids: [Int]) -> HTTPResponse {
        let json = ids.map { id in
            FakeHTTPTransport.threadJSON(
                id: String(id), subjectURL: "https://api.github.com/repos/octo/app/releases/\(id)", type: "Release")
        }
        return PollerFixture.ok(body: Data("[\(json.joined(separator: ","))]".utf8))
    }

    static func isRelease(_ request: URLRequest) -> Bool {
        request.url?.path().contains("/releases/") == true
    }

    /// 通知の取得には `notifications` を順に返し（尽きたら通信の失敗）、リリースの取得にはタグ `rust-v1.0.0` を返す。
    func respondWithReleases(_ fixture: PollerFixture, notifications: [HTTPResponse]) {
        let queue = LockedValue(notifications)
        fixture.transport.setHandler { request throws(TransportError) in
            if Self.isRelease(request) {
                return HTTPResponse(statusCode: 200, body: Data(#"{"tag_name": "rust-v1.0.0"}"#.utf8))
            }
            guard let next = queue.withLock({ $0.isEmpty ? nil : $0.removeFirst() }) else {
                throw .network(code: URLError.Code.notConnectedToInternet.rawValue)
            }
            return next
        }
    }

    @Test func fetchesTheTagOfNewReleasesBeforePublishing() async throws {
        let fixture = try PollerFixture()
        respondWithReleases(fixture, notifications: [Self.releases([1]), Self.releases([1, 2])])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(2)
        let first = try #require(firstUpdate(containing: "2", fixture))
        #expect(first.threads.first { $0.id == "2" }?.details == Self.tagged)
        let releaseRequests = fixture.transport.requests.filter(Self.isRelease)
        let releaseURLs = releaseRequests.compactMap { $0.url?.absoluteString }
        #expect(releaseURLs.contains("https://api.github.com/repos/octo/app/releases/2"))
        #expect(
            releaseRequests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer test-token-alice" })
        fixture.poller.stop()
    }

    @Test func tagsTheFirstListAfterPublishing() async throws {
        let fixture = try PollerFixture()
        respondWithReleases(fixture, notifications: [Self.releases([1, 2])])
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        let first = try #require(fixture.updates.value.first { $0.phase != .loading })
        #expect(first.threads.allSatisfy { $0.details == nil })
        #expect(fixture.last?.threads.allSatisfy { $0.details == Self.tagged } == true)
        #expect(fixture.transport.requests.filter(Self.isRelease).count == 2)
        fixture.poller.stop()
    }
}
