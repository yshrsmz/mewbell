import Foundation
import Testing

@testable import Mewbell

/// `GitHubAPIClient.markThreadDone` のテスト。
struct MarkThreadDoneTests {
    private let github: APIEndpoints
    private let token: AccessToken

    init() throws {
        github = try #require(APIEndpoints(host: "github.com"))
        token = try #require(AccessToken(ghOutput: Data("test-token-alice".utf8)))
    }

    private func markDone(_ response: HTTPResponse) async -> (ThreadActionResult, FakeHTTPTransport) {
        let transport = FakeHTTPTransport { _ in response }
        let result = await GitHubAPIClient(transport: transport).markThreadDone(
            endpoints: github, token: token, threadID: "123")
        return (result, transport)
    }

    @Test func buildsTheDeleteRequest() async throws {
        let (result, transport) = await markDone(HTTPResponse(statusCode: 204))
        #expect(result == .succeeded)
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.absoluteString == "https://api.github.com/notifications/threads/123")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
        #expect(request.httpBody == nil)
    }

    /// Done に固有の成功（`204` / `404`）と、既読では成功の `205` を失敗にすること。
    /// そのほかの状態コードの分類は `MarkThreadReadTests.classifiesTheStatus` で確かめる。
    @Test(arguments: [
        (HTTPResponse(statusCode: 204), ThreadActionResult.succeeded),
        (HTTPResponse(statusCode: 404), .succeeded),
        (HTTPResponse(statusCode: 205), .failed(.unexpectedStatus(205))),
    ])
    func classifiesTheStatus(_ response: HTTPResponse, _ expected: ThreadActionResult) async {
        let (result, _) = await markDone(response)
        #expect(result == expected)
    }
}

/// `GitHubAPIClient.markAllRead` のテスト。
struct MarkAllReadTests {
    private let github: APIEndpoints
    private let token: AccessToken
    /// 2026-10-09T12:34:56Z
    private let lastReadAt = Date(timeIntervalSince1970: 1_791_549_296)

    init() throws {
        github = try #require(APIEndpoints(host: "github.com"))
        token = try #require(AccessToken(ghOutput: Data("test-token-alice".utf8)))
    }

    private func markAllRead(_ response: HTTPResponse) async -> (ThreadActionResult, FakeHTTPTransport) {
        let transport = FakeHTTPTransport { _ in response }
        let result = await GitHubAPIClient(transport: transport).markAllRead(
            endpoints: github, token: token, lastReadAt: lastReadAt)
        return (result, transport)
    }

    @Test func buildsThePutRequest() async throws {
        let (result, transport) = await markAllRead(HTTPResponse(statusCode: 205))
        #expect(result == .succeeded)
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.absoluteString == "https://api.github.com/notifications")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json.count == 2)
        #expect(json["last_read_at"] as? String == "2026-10-09T12:34:56Z")
        #expect(json["read"] as? Bool == true)
    }

    /// すべて既読に固有の成功（`202` / `205` / `304`）と、スレッドの操作では成功の `404` を失敗にすること。
    @Test(arguments: [
        (HTTPResponse(statusCode: 202), ThreadActionResult.succeeded),
        (HTTPResponse(statusCode: 205), .succeeded),
        (HTTPResponse(statusCode: 304), .succeeded),
        (HTTPResponse(statusCode: 404), .failed(.unexpectedStatus(404))),
    ])
    func classifiesTheStatus(_ response: HTTPResponse, _ expected: ThreadActionResult) async {
        let (result, _) = await markAllRead(response)
        #expect(result == expected)
    }
}
