import Foundation
import Testing

@testable import Mewbell

// Release のスレッドの `GitHubAPIClient.fetchDetails` のリクエストと結果（github-api「リリースのタグの取得のリクエスト」）
extension ThreadDetailsRequestTests {
    private func releaseThread(
        host: String = "github.com", repository: String = "octo/app",
        subjectURL: String = "https://api.github.com/repos/octo/app/releases/12"
    ) throws -> (NotificationThread, APIEndpoints) {
        try thread(host: host, repository: repository, subjectURL: subjectURL, type: "Release")
    }

    /// すべてのリクエストに `response` を返すトランスポートで取る。
    private func fetch(_ thread: NotificationThread, _ endpoints: APIEndpoints, _ response: HTTPResponse)
        async -> (ThreadDetailsFetchResult, FakeHTTPTransport)
    {
        let transport = FakeHTTPTransport { _ in response }
        return (await fetch(thread, endpoints, transport), transport)
    }

    private static func release(tagName: String, htmlURL: String = "https://github.com/octo/app/releases/tag/x")
        -> HTTPResponse
    {
        let body = #"{"id": 12, "tag_name": "\#(tagName)", "html_url": "\#(htmlURL)", "body": "notes"}"#
        return HTTPResponse(statusCode: 200, body: Data(body.utf8))
    }

    private static func found(_ tag: String) -> ThreadDetailsFetchResult {
        .found(ThreadDetails(state: nil, event: nil, releaseTag: tag))
    }

    @Test func fetchesTheTag() async throws {
        let (thread, endpoints) = try releaseThread(
            repository: "openai/codex", subjectURL: "https://api.github.com/repos/openai/codex/releases/413167889")
        let (result, transport) = await fetch(thread, endpoints, Self.release(tagName: "rust-v0.163.0-alpha.10.1"))
        #expect(result == Self.found("rust-v0.163.0-alpha.10.1"))
        #expect(
            transport.requests.map { $0.url?.absoluteString } == [
                "https://api.github.com/repos/openai/codex/releases/413167889"
            ])
        #expect(transport.requests.first?.httpMethod == "GET")
        #expect(transport.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer test-token-alice")
    }

    @Test func buildsTheReleaseURLOnGHES() async throws {
        let (thread, endpoints) = try releaseThread(
            host: "ghe.example.com", repository: "team/svc",
            subjectURL: "https://ghe.example.com/api/v3/repos/team/svc/releases/12")
        let (_, transport) = await fetch(thread, endpoints, Self.release(tagName: "v1.0.0"))
        #expect(
            transport.requests.map { $0.url?.absoluteString } == [
                "https://ghe.example.com/api/v3/repos/team/svc/releases/12"
            ])
    }

    @Test func buildsTheReleaseURLFromTheValidatedRepository() async throws {
        let (thread, endpoints) = try releaseThread(subjectURL: "https://api.github.com/repos/OCTO/App/releases/12")
        let (_, transport) = await fetch(thread, endpoints, Self.release(tagName: "v1.0.0"))
        #expect(transport.requests.first?.url?.absoluteString == "https://api.github.com/repos/octo/app/releases/12")
    }

    @Test func doesNotUseTheHTMLURL() async throws {
        let (thread, endpoints) = try releaseThread()
        let response = Self.release(
            tagName: "v1.0.0", htmlURL: "https://evil.example.com/octo/app/releases/tag/v1.0.0")
        let (result, _) = await fetch(thread, endpoints, response)
        #expect(result == Self.found("v1.0.0"))
        var tagged = thread
        tagged.details = ThreadDetails(state: nil, event: nil, releaseTag: "v1.0.0")
        let opened = try #require(ThreadWebURL.make(for: tagged, endpoints: endpoints))
        #expect(opened.absoluteString == "https://github.com/octo/app/releases/tag/v1.0.0")
    }

    /// リリースの ID を持つかどうかの判定は `ThreadWebURL.releaseID` のテストで確かめる
    @Test func sendsNothingWithoutAReleaseID() async throws {
        let (thread, endpoints) = try releaseThread(subjectURL: "https://evil.example.com/repos/octo/app/releases/12")
        let (result, transport) = await fetch(thread, endpoints, Self.release(tagName: "v1.0.0"))
        #expect(result == .unavailable)
        #expect(transport.requests.isEmpty)
    }

    @Test(arguments: ["../../settings", "v1 0", "", "a//b"])
    func treatsAnInvalidTagAsUnavailable(_ tag: String) async throws {
        let (thread, endpoints) = try releaseThread()
        #expect(await fetch(thread, endpoints, Self.release(tagName: tag)).0 == .unavailable)
    }

    @Test(arguments: [404, 410, 422, 403])
    func treatsAMissingReleaseAsUnavailable(_ status: Int) async throws {
        let (thread, endpoints) = try releaseThread()
        #expect(await fetch(thread, endpoints, HTTPResponse(statusCode: status)).0 == .unavailable)
    }

    @Test func unauthorizedForARelease() async throws {
        let (thread, endpoints) = try releaseThread()
        #expect(await fetch(thread, endpoints, HTTPResponse(statusCode: 401)).0 == .unauthorized)
    }

    @Test func rateLimitedForARelease() async throws {
        let (thread, endpoints) = try releaseThread()
        let reset = now.addingTimeInterval(600)
        let forbidden = HTTPResponse(
            statusCode: 403,
            headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": String(Int(reset.timeIntervalSince1970))])
        #expect(await fetch(thread, endpoints, forbidden).0 == .rateLimited(retryAt: reset))
        let tooMany = HTTPResponse(statusCode: 429, headers: ["Retry-After": "120"])
        #expect(await fetch(thread, endpoints, tooMany).0 == .rateLimited(retryAt: now.addingTimeInterval(120)))
        #expect(await fetch(thread, endpoints, FakeHTTPTransport.secondaryRateLimit()).0 == .rateLimited(retryAt: now))
    }

    @Test func temporaryFailuresForARelease() async throws {
        let (thread, endpoints) = try releaseThread()
        #expect(await fetch(thread, endpoints, HTTPResponse(statusCode: 500)).0 == .failed(.unexpectedStatus(500)))
        let redirect = HTTPResponse(statusCode: 302, headers: ["Location": "https://evil.example.com/"])
        #expect(await fetch(thread, endpoints, redirect).0 == .failed(.redirect))
        for body in ["{}", #"{"tag_name": 1}"#, "[]", "not json"] {
            let response = HTTPResponse(statusCode: 200, body: Data(body.utf8))
            #expect(await fetch(thread, endpoints, response).0 == .failed(.malformedBody))
        }
    }
}
