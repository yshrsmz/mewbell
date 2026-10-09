import Foundation
import Testing

@testable import Mewbell

struct ThreadIDTests {
    @Test(arguments: ["", "123456789012345678901", "12a", "../1", "１２３", "-1", "1 2", "1/2"])
    func rejects(_ id: String) {
        #expect(!ThreadID.isValid(id))
    }

    @Test(arguments: ["1", "12345678901234567890", "0"])
    func accepts(_ id: String) {
        #expect(ThreadID.isValid(id))
    }
}

struct MarkThreadReadTests {
    private let github: APIEndpoints
    private let ghes: APIEndpoints
    private let token: AccessToken

    init() throws {
        github = try #require(APIEndpoints(host: "github.com"))
        ghes = try #require(APIEndpoints(host: "ghe.example.com"))
        token = try #require(AccessToken(ghOutput: Data("test-token-alice".utf8)))
    }

    private func markRead(
        _ response: HTTPResponse, endpoints: APIEndpoints? = nil, threadID: String = "123"
    ) async -> (ThreadActionResult, FakeHTTPTransport) {
        let transport = FakeHTTPTransport { _ in response }
        let result = await GitHubAPIClient(transport: transport).markThreadRead(
            endpoints: endpoints ?? github, token: token, threadID: threadID)
        return (result, transport)
    }

    @Test func buildsThePatchRequest() async throws {
        let (result, transport) = await markRead(HTTPResponse(statusCode: 205))
        #expect(result == .succeeded)
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.absoluteString == "https://api.github.com/notifications/threads/123")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token-alice")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2022-11-28")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Mewbell/") == true)
        #expect(request.value(forHTTPHeaderField: "If-Modified-Since") == nil)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
        #expect(request.httpBody == nil)
    }

    @Test func usesTheGHESBasePath() async {
        let (_, transport) = await markRead(HTTPResponse(statusCode: 205), endpoints: ghes, threadID: "77")
        #expect(
            transport.requests.first?.url?.absoluteString == "https://ghe.example.com/api/v3/notifications/threads/77")
    }

    @Test(arguments: [
        (HTTPResponse(statusCode: 205), ThreadActionResult.succeeded),
        (HTTPResponse(statusCode: 304), .succeeded),
        (HTTPResponse(statusCode: 404), .succeeded),
        (HTTPResponse(statusCode: 401), .unauthorized),
        (HTTPResponse(statusCode: 403, headers: ["X-RateLimit-Remaining": "0"]), .rateLimited),
        (HTTPResponse(statusCode: 403, headers: ["Retry-After": "60"]), .rateLimited),
        (HTTPResponse(statusCode: 429), .rateLimited),
        (HTTPResponse(statusCode: 403), .failed(.unexpectedStatus(403))),
        (HTTPResponse(statusCode: 403, headers: ["Retry-After": "soon"]), .failed(.unexpectedStatus(403))),
        (HTTPResponse(statusCode: 422), .failed(.unexpectedStatus(422))),
        (HTTPResponse(statusCode: 500), .failed(.unexpectedStatus(500))),
        (HTTPResponse(statusCode: 307, headers: ["Location": "https://evil.example.com/"]), .failed(.redirect)),
    ])
    func classifiesTheStatus(_ response: HTTPResponse, _ expected: ThreadActionResult) async {
        let (result, _) = await markRead(response)
        #expect(result == expected)
    }

    @Test(arguments: ["123/../../user", "abc", ""])
    func sendsNothingForAnInvalidID(_ id: String) async {
        let (result, transport) = await markRead(HTTPResponse(statusCode: 205), threadID: id)
        #expect(result == .failed(.rejectedURL))
        #expect(transport.requests.isEmpty)
    }
}
