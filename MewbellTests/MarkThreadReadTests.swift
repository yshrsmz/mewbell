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
    private let token: AccessToken

    init() throws {
        github = try #require(APIEndpoints(host: "github.com"))
        token = try #require(AccessToken(ghOutput: Data("test-token-alice".utf8)))
    }

    private func markRead(
        _ response: HTTPResponse, threadID: String = "123"
    ) async -> (ThreadActionResult, FakeHTTPTransport) {
        let transport = FakeHTTPTransport { _ in response }
        let result = await GitHubAPIClient(transport: transport).markThreadRead(
            endpoints: github, token: token, threadID: threadID)
        return (result, transport)
    }

    @Test func buildsThePatchRequest() async throws {
        let (result, transport) = await markRead(HTTPResponse(statusCode: 205))
        #expect(result == .succeeded)
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.absoluteString == "https://api.github.com/notifications/threads/123")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
        #expect(request.httpBody == nil)
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
        // 待ち時間のヘッダーが無い二次レート制限は本文で見分ける
        (FakeHTTPTransport.secondaryRateLimit(), .rateLimited),
        (
            HTTPResponse(statusCode: 403, body: Data(#"{"message": "Resource not accessible by integration"}"#.utf8)),
            .failed(.unexpectedStatus(403))
        ),
        (HTTPResponse(statusCode: 422), .failed(.unexpectedStatus(422))),
        (HTTPResponse(statusCode: 500), .failed(.unexpectedStatus(500))),
        (HTTPResponse(statusCode: 307, headers: ["Location": "https://evil.example.com/"]), .failed(.redirect)),
    ])
    func classifiesTheStatus(_ response: HTTPResponse, _ expected: ThreadActionResult) async {
        let (result, _) = await markRead(response)
        #expect(result == expected)
    }

    /// ID の形の判定は `ThreadIDTests` で確かめる。ここでは、判定を通らない ID では何も送らないことを確かめる
    @Test func sendsNothingForAnInvalidID() async {
        let (result, transport) = await markRead(HTTPResponse(statusCode: 205), threadID: "123/../../user")
        #expect(result == .failed(.rejectedURL))
        #expect(transport.requests.isEmpty)
    }
}
