import Foundation
import Testing

@testable import Mewbell

struct ThreadDetailsCacheTests {
    private let now = Date(timeIntervalSince1970: 1_791_460_800)
    private let open = ThreadDetails(state: .open, event: ThreadEvent(kind: .commented, actor: "bob"))

    private func thread(_ id: String, updatedAt: TimeInterval = 0, numbered: Bool = true) throws -> NotificationThread {
        NotificationThread(
            id: id, reason: "subscribed", updatedAt: Date(timeIntervalSince1970: updatedAt), title: "Thread \(id)",
            kind: .issue, subjectURL: nil, repository: try #require(RepositoryName(fullName: "octo/app")),
            subjectNumber: numbered ? id : nil)
    }

    @Test func attachesOnlyWhenTheUpdateMatches() throws {
        var cache = ThreadDetailsCache()
        cache.record(.found(open), for: try thread("1", updatedAt: 10))
        #expect(cache.attach(to: [try thread("1", updatedAt: 10)]).first?.details == open)
        #expect(cache.attach(to: [try thread("1", updatedAt: 20)]).first?.details == nil)
        #expect(cache.attach(to: [try thread("2", updatedAt: 10)]).first?.details == nil)
    }

    @Test func picksPendingThreadsNewestFirst() throws {
        var cache = ThreadDetailsCache()
        let threads = [
            try thread("1", updatedAt: 10), try thread("2", updatedAt: 30), try thread("3", updatedAt: 20),
            try thread("4", updatedAt: 40, numbered: false),
        ]
        #expect(cache.pending(in: threads, newOnly: false, limit: 2, now: now).map(\.id) == ["2", "3"])
        cache.record(.found(open), for: threads[1])
        cache.record(.unavailable, for: threads[2])
        #expect(cache.pending(in: threads, newOnly: false, limit: 10, now: now).map(\.id) == ["1"])
    }

    @Test func retriesTemporaryFailures() throws {
        var cache = ThreadDetailsCache()
        let one = try thread("1")
        let recordedFailure = cache.record(.failed(.network(code: -1)), for: one)
        let recordedUnauthorized = cache.record(.unauthorized, for: one)
        #expect(!recordedFailure && !recordedUnauthorized)
        #expect(cache.pending(in: [one], newOnly: false, limit: 10, now: now).map(\.id) == ["1"])
    }

    @Test func givesUpAfterRepeatedFailures() throws {
        var cache = ThreadDetailsCache()
        let one = try thread("1", updatedAt: 10)
        cache.record(.failed(.redirect), for: one)
        cache.record(.unauthorized, for: one)
        #expect(cache.pending(in: [one], newOnly: false, limit: 10, now: now).map(\.id) == ["1"])
        cache.record(.failed(.redirect), for: one)
        #expect(cache.pending(in: [one], newOnly: false, limit: 10, now: now).isEmpty)
        #expect(cache.attach(to: [one]).first?.details == nil)
        let advanced = try thread("1", updatedAt: 20)
        #expect(cache.pending(in: [advanced], newOnly: false, limit: 10, now: now).map(\.id) == ["1"])
    }

    @Test func countsFailuresPerUpdate() throws {
        var cache = ThreadDetailsCache()
        cache.record(.failed(.redirect), for: try thread("1", updatedAt: 10))
        cache.record(.failed(.redirect), for: try thread("1", updatedAt: 10))
        // updated_at が進んだら数え直す
        cache.record(.failed(.redirect), for: try thread("1", updatedAt: 20))
        let advanced = try thread("1", updatedAt: 20)
        #expect(cache.pending(in: [advanced], newOnly: false, limit: 10, now: now).map(\.id) == ["1"])
    }

    @Test func refetchesWhenTheUpdateAdvances() throws {
        var cache = ThreadDetailsCache()
        cache.record(.found(open), for: try thread("1", updatedAt: 10))
        #expect(
            cache.pending(in: [try thread("1", updatedAt: 20)], newOnly: false, limit: 10, now: now).map(\.id) == ["1"])
    }

    @Test func newOnlyNeedsAPreviousList() throws {
        var cache = ThreadDetailsCache()
        let first = [try thread("1", updatedAt: 10), try thread("2", updatedAt: 10)]
        #expect(cache.pending(in: first, newOnly: true, limit: 10, now: now).isEmpty)
        cache.listed(first)
        let second = [try thread("1", updatedAt: 10), try thread("2", updatedAt: 20), try thread("3", updatedAt: 5)]
        #expect(cache.pending(in: second, newOnly: true, limit: 10, now: now).map(\.id) == ["2", "3"])
    }

    @Test func dropsThreadsThatLeftTheList() throws {
        var cache = ThreadDetailsCache()
        cache.record(.found(open), for: try thread("1"))
        cache.record(.found(open), for: try thread("2"))
        cache.listed([try thread("2")])
        #expect(cache.attach(to: [try thread("1")]).first?.details == nil)
        #expect(cache.attach(to: [try thread("2")]).first?.details == open)
    }

    @Test func pausesUntilTheRateLimitEnds() throws {
        var cache = ThreadDetailsCache()
        let one = try thread("1")
        cache.record(.rateLimited(retryAt: now.addingTimeInterval(600)), for: one)
        #expect(cache.pending(in: [one], newOnly: false, limit: 10, now: now.addingTimeInterval(60)).isEmpty)
        #expect(
            cache.pending(in: [one], newOnly: false, limit: 10, now: now.addingTimeInterval(600)).map(\.id) == ["1"])
    }

    @Test func pausesAtLeastAMinuteOnRateLimits() throws {
        var cache = ThreadDetailsCache()
        let one = try thread("1")
        cache.record([(one, .rateLimited(retryAt: now))], now: now)
        #expect(cache.pending(in: [one], newOnly: false, limit: 10, now: now.addingTimeInterval(59)).isEmpty)
        #expect(cache.pending(in: [one], newOnly: false, limit: 10, now: now.addingTimeInterval(60)).map(\.id) == ["1"])
    }

    @Test func resetForgetsEverything() throws {
        var cache = ThreadDetailsCache()
        let one = try thread("1")
        cache.record(.found(open), for: one)
        cache.listed([one])
        cache.reset()
        #expect(cache.attach(to: [one]).first?.details == nil)
        #expect(cache.pending(in: [one], newOnly: true, limit: 10, now: now).isEmpty)
    }
}

struct ThreadDetailsFetcherTests {
    @Test func doesNotReportCancelledFetchesAsFailures() async throws {
        let transport = FakeHTTPTransport { _ in HTTPResponse(statusCode: 200, body: Data("[]".utf8)) }
        transport.pausedWhere.value = { _ in true }
        let endpoints = try #require(APIEndpoints(host: "github.com"))
        let token = try #require(AccessToken(ghOutput: Data("test-token-alice".utf8)))
        let json = FakeHTTPTransport.threadJSON(id: "1", subjectURL: "https://api.github.com/repos/octo/app/issues/1")
        let threads = try #require(NotificationThread.decodeList(from: Data("[\(json)]".utf8), endpoints: endpoints))
        let fetcher = ThreadDetailsFetcher(client: GitHubAPIClient(transport: transport), endpoints: endpoints)
        let task = Task { await fetcher.fetch(threads, token: token, timeout: .seconds(20)) }
        await waitUntil { !transport.requests.isEmpty }
        task.cancel()
        #expect(await task.value.isEmpty)
    }

    @Test func reportsTimedOutFetchesAsFailures() async throws {
        let transport = FakeHTTPTransport { _ in HTTPResponse(statusCode: 200, body: Data("[]".utf8)) }
        transport.pausedWhere.value = { _ in true }
        let endpoints = try #require(APIEndpoints(host: "github.com"))
        let token = try #require(AccessToken(ghOutput: Data("test-token-alice".utf8)))
        let json = FakeHTTPTransport.threadJSON(id: "1", subjectURL: "https://api.github.com/repos/octo/app/issues/1")
        let threads = try #require(NotificationThread.decodeList(from: Data("[\(json)]".utf8), endpoints: endpoints))
        let fetcher = ThreadDetailsFetcher(client: GitHubAPIClient(transport: transport), endpoints: endpoints)
        let results = await fetcher.fetch(threads, token: token, timeout: .milliseconds(50))
        #expect(results.map(\.1) == [.failed(.network(code: URLError.Code.timedOut.rawValue))])
    }
}
