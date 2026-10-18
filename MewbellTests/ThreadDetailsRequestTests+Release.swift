import Foundation
import Testing

@testable import Mewbell

// Release のスレッドの `GitHubAPIClient.fetchDetails` のリクエストと結果（github-api「リリースのタグの取得のリクエスト」
// 「リリースのタグの取得の tag_name」「リリースのタグの取得のレスポンス」）。共通の取得の失敗は Issue の経路で確かめる
extension ThreadDetailsRequestTests {
    private func releaseThread(
        repository: String = "octo/app", subjectURL: String = "https://api.github.com/repos/octo/app/releases/12"
    ) throws -> (NotificationThread, APIEndpoints) {
        try thread(repository: repository, subjectURL: subjectURL, type: "Release")
    }

    /// すべてのリクエストに `response` を返すトランスポートで取る。
    private func fetch(_ thread: NotificationThread, _ endpoints: APIEndpoints, _ response: HTTPResponse)
        async -> (ThreadDetailsFetchResult, FakeHTTPTransport)
    {
        let transport = FakeHTTPTransport { _ in response }
        return (await fetch(thread, endpoints, transport), transport)
    }

    /// `html_url` は攻撃者のホストにしておく（使わないことは `ReleaseSummary` の型が保証する）。
    private static func release(tagName: String) -> HTTPResponse {
        let body =
            #"{"id": 12, "tag_name": "\#(tagName)", "html_url": "https://evil.example.com/octo/app/releases/tag/x", "#
            + #""body": "notes"}"#
        return HTTPResponse(statusCode: 200, body: Data(body.utf8))
    }

    private static func found(_ tag: String) -> ThreadDetailsFetchResult {
        .found(ThreadDetails(state: nil, event: nil, resource: .release(tag: tag)))
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
    }

    @Test func buildsTheReleaseURLFromTheValidatedRepository() async throws {
        let (thread, endpoints) = try releaseThread(subjectURL: "https://api.github.com/repos/OCTO/App/releases/12")
        let (_, transport) = await fetch(thread, endpoints, Self.release(tagName: "v1.0.0"))
        #expect(transport.requests.first?.url?.absoluteString == "https://api.github.com/repos/octo/app/releases/12")
    }

    /// タグの形の検証は `ReleaseTagTests` で確かめる
    @Test func treatsAnInvalidTagAsUnavailable() async throws {
        let (thread, endpoints) = try releaseThread()
        #expect(await fetch(thread, endpoints, Self.release(tagName: "../../settings")).0 == .unavailable)
    }

    @Test func treatsAMissingReleaseAsUnavailable() async throws {
        let (thread, endpoints) = try releaseThread()
        #expect(await fetch(thread, endpoints, HTTPResponse(statusCode: 404)).0 == .unavailable)
    }

    /// 共通の取得の失敗は Issue の経路で確かめる。ここではリリースのボディの読み取りだけを見る
    @Test func treatsABodyWithoutATagAsMalformed() async throws {
        let (thread, endpoints) = try releaseThread()
        let response = HTTPResponse(statusCode: 200, body: Data("{}".utf8))
        #expect(await fetch(thread, endpoints, response).0 == .failed(.malformedBody))
    }
}
