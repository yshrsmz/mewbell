import Foundation
import Testing

@testable import Mewbell

/// `GitHubAPIClient.markThreadDone` のテスト。
struct MarkThreadDoneTests {
    private let github: APIEndpoints
    private let gheCloud: APIEndpoints
    private let token: AccessToken

    init() throws {
        github = try #require(APIEndpoints(host: "github.com"))
        gheCloud = try #require(APIEndpoints(host: "acme.ghe.com"))
        token = try #require(AccessToken(ghOutput: Data("test-token-alice".utf8)))
    }

    private func markDone(
        _ response: HTTPResponse, endpoints: APIEndpoints? = nil, threadID: String = "123"
    ) async -> (ThreadActionResult, FakeHTTPTransport) {
        let transport = FakeHTTPTransport { _ in response }
        let result = await GitHubAPIClient(transport: transport).markThreadDone(
            endpoints: endpoints ?? github, token: token, threadID: threadID)
        return (result, transport)
    }

    @Test func buildsTheDeleteRequest() async throws {
        let (result, transport) = await markDone(HTTPResponse(statusCode: 204))
        #expect(result == .succeeded)
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.absoluteString == "https://api.github.com/notifications/threads/123")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token-alice")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2022-11-28")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Mewbell/") == true)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
        #expect(request.httpBody == nil)
    }

    @Test func usesTheGHECloudBase() async {
        let (_, transport) = await markDone(HTTPResponse(statusCode: 204), endpoints: gheCloud, threadID: "77")
        #expect(transport.requests.first?.url?.absoluteString == "https://api.acme.ghe.com/notifications/threads/77")
    }

    @Test(arguments: [
        (HTTPResponse(statusCode: 204), ThreadActionResult.succeeded),
        (HTTPResponse(statusCode: 404), .succeeded),
        (HTTPResponse(statusCode: 401), .unauthorized),
        (HTTPResponse(statusCode: 403, headers: ["X-RateLimit-Remaining": "0"]), .rateLimited),
        (HTTPResponse(statusCode: 429), .rateLimited),
        (HTTPResponse(statusCode: 403), .failed(.unexpectedStatus(403))),
        (HTTPResponse(statusCode: 205), .failed(.unexpectedStatus(205))),
        (HTTPResponse(statusCode: 422), .failed(.unexpectedStatus(422))),
        (HTTPResponse(statusCode: 500), .failed(.unexpectedStatus(500))),
        (HTTPResponse(statusCode: 307, headers: ["Location": "https://evil.example.com/"]), .failed(.redirect)),
    ])
    func classifiesTheStatus(_ response: HTTPResponse, _ expected: ThreadActionResult) async {
        let (result, transport) = await markDone(response)
        #expect(result == expected)
        // リダイレクトの先には送らない
        #expect(transport.requests.allSatisfy { $0.url?.host() == "api.github.com" })
        #expect(transport.requests.count == 1)
    }

    @Test(arguments: ["123/../../user", "abc", ""])
    func sendsNothingForAnInvalidID(_ id: String) async {
        let (result, transport) = await markDone(HTTPResponse(statusCode: 204), threadID: id)
        #expect(result == .failed(.rejectedURL))
        #expect(transport.requests.isEmpty)
    }
}

/// `GitHubAPIClient.markAllRead` のテスト。
struct MarkAllReadTests {
    private let github: APIEndpoints
    private let ghes: APIEndpoints
    private let token: AccessToken
    /// 2026-10-09T12:34:56Z
    private let lastReadAt = Date(timeIntervalSince1970: 1_791_549_296)

    init() throws {
        github = try #require(APIEndpoints(host: "github.com"))
        ghes = try #require(APIEndpoints(host: "ghe.example.com"))
        token = try #require(AccessToken(ghOutput: Data("test-token-alice".utf8)))
    }

    private func markAllRead(
        _ response: HTTPResponse, endpoints: APIEndpoints? = nil
    ) async -> (ThreadActionResult, FakeHTTPTransport) {
        let transport = FakeHTTPTransport { _ in response }
        let result = await GitHubAPIClient(transport: transport).markAllRead(
            endpoints: endpoints ?? github, token: token, lastReadAt: lastReadAt)
        return (result, transport)
    }

    @Test func buildsThePutRequest() async throws {
        let (result, transport) = await markAllRead(HTTPResponse(statusCode: 205))
        #expect(result == .succeeded)
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.absoluteString == "https://api.github.com/notifications")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token-alice")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2022-11-28")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json.count == 2)
        #expect(json["last_read_at"] as? String == "2026-10-09T12:34:56Z")
        #expect(json["read"] as? Bool == true)
        #expect(String(bytes: body, encoding: .utf8)?.contains("test-token") == false)
    }

    @Test func usesTheGHESBasePath() async {
        let (_, transport) = await markAllRead(HTTPResponse(statusCode: 205), endpoints: ghes)
        #expect(transport.requests.first?.url?.absoluteString == "https://ghe.example.com/api/v3/notifications")
    }

    @Test(arguments: [
        (HTTPResponse(statusCode: 202), ThreadActionResult.succeeded),
        (HTTPResponse(statusCode: 205), .succeeded),
        (HTTPResponse(statusCode: 304), .succeeded),
        (HTTPResponse(statusCode: 401), .unauthorized),
        (HTTPResponse(statusCode: 403, headers: ["Retry-After": "60"]), .rateLimited),
        (HTTPResponse(statusCode: 403, headers: ["X-RateLimit-Remaining": "0"]), .rateLimited),
        (HTTPResponse(statusCode: 403), .failed(.unexpectedStatus(403))),
        (HTTPResponse(statusCode: 422), .failed(.unexpectedStatus(422))),
        (HTTPResponse(statusCode: 500), .failed(.unexpectedStatus(500))),
        (HTTPResponse(statusCode: 302, headers: ["Location": "https://evil.example.com/"]), .failed(.redirect)),
    ])
    func classifiesTheStatus(_ response: HTTPResponse, _ expected: ThreadActionResult) async {
        let (result, transport) = await markAllRead(response)
        #expect(result == expected)
        #expect(transport.requests.count == 1)
    }
}
