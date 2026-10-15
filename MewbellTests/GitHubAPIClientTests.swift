import Foundation
import Testing

@testable import Mewbell

struct URLSessionTransportTests {
    @Test func doesNotCacheOrKeepCookiesOrSharedHeaders() {
        let configuration = URLSessionTransport().session.configuration
        #expect(configuration.urlCache == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
        #expect(configuration.httpCookieStorage == nil)
        #expect(!configuration.httpShouldSetCookies)
        #expect(configuration.httpCookieAcceptPolicy == .never)
        #expect(configuration.urlCredentialStorage == nil)
        #expect(configuration.httpAdditionalHeaders?.isEmpty ?? true)
    }

    @Test func rejectsEveryRedirect() throws {
        let transport = URLSessionTransport()
        let delegate = try #require(transport.session.delegate as? RedirectRejectingDelegate)
        let original = try #require(URL(string: "https://api.github.com/notifications"))
        let task = transport.session.dataTask(with: original)
        for location in ["https://evil.example.com/", "https://api.github.com/notifications?page=2"] {
            let response = try #require(
                HTTPURLResponse(url: original, statusCode: 302, httpVersion: nil, headerFields: ["Location": location]))
            let next = URLRequest(url: try #require(URL(string: location)))
            let result = LockedValue<URLRequest??>(nil)
            delegate.urlSession(
                transport.session, task: task, willPerformHTTPRedirection: response, newRequest: next
            ) { request in result.value = .some(request) }
            #expect(result.value == .some(nil))
        }
        task.cancel()
    }
}

struct GitHubAPIClientTests {
    private let github: APIEndpoints
    private let ghes: APIEndpoints
    private let aliceToken: AccessToken
    private let now = Date(timeIntervalSince1970: 1_791_460_800)

    init() throws {
        github = try #require(APIEndpoints(host: "github.com"))
        ghes = try #require(APIEndpoints(host: "ghe.example.com"))
        aliceToken = try #require(AccessToken(ghOutput: Data("test-token-alice".utf8)))
    }

    private func client(_ transport: FakeHTTPTransport) -> GitHubAPIClient {
        let now = now
        return GitHubAPIClient(transport: transport, now: { now })
    }

    private static func ok(
        _ body: Data = FakeHTTPTransport.page(1...1), _ headers: [String: String] = [:]
    ) -> HTTPResponse {
        HTTPResponse(
            statusCode: 200,
            headers: ["X-OAuth-Scopes": "repo, read:org", "Last-Modified": "LM-1", "X-Poll-Interval": "60"]
                .merging(headers) { $1 },
            body: body)
    }

    @Test func buildsTheRequest() async throws {
        let transport = FakeHTTPTransport { _ in HTTPResponse(statusCode: 200, body: Data("[]".utf8)) }
        _ = await client(transport).fetchNotifications(endpoints: github, token: aliceToken, ifModifiedSince: nil)
        let request = try #require(transport.requests.first)
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "https")
        #expect(components.host == "api.github.com")
        #expect(components.path == "/notifications")
        #expect(
            Set(components.queryItems ?? [])
                == [
                    .init(name: "all", value: "false"), .init(name: "participating", value: "false"),
                    .init(name: "per_page", value: "50"),
                ])
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token-alice")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2022-11-28")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Mewbell/") == true)
        #expect(request.value(forHTTPHeaderField: "If-Modified-Since") == nil)
    }

    @Test func usesTheGHESBasePath() async throws {
        let transport = FakeHTTPTransport { _ in HTTPResponse(statusCode: 200, body: Data("[]".utf8)) }
        _ = await client(transport).fetchNotifications(endpoints: ghes, token: aliceToken, ifModifiedSince: nil)
        #expect(transport.requests.first?.url?.path() == "/api/v3/notifications")
    }

    @Test func sendsIfModifiedSinceOnTheFirstPageOnly() async throws {
        let transport = FakeHTTPTransport { request in
            if request.url?.query()?.contains("page=2") == true {
                return HTTPResponse(statusCode: 200, body: FakeHTTPTransport.page(2...2))
            }
            return HTTPResponse(
                statusCode: 200, headers: ["Link": #"<https://api.github.com/notifications?page=2>; rel="next""#],
                body: FakeHTTPTransport.page(1...1))
        }
        _ = await client(transport).fetchNotifications(endpoints: github, token: aliceToken, ifModifiedSince: "LM-0")
        #expect(transport.requests.map { $0.value(forHTTPHeaderField: "If-Modified-Since") } == ["LM-0", nil])
    }

    @Test func returnsNotModified() async {
        let transport = FakeHTTPTransport { _ in HTTPResponse(statusCode: 304, headers: ["X-Poll-Interval": "90"]) }
        let result = await client(transport).fetchNotifications(
            endpoints: github, token: aliceToken, ifModifiedSince: "LM-0")
        #expect(result == .notModified(pollInterval: 90))
    }

    @Test func followsTwoPages() async throws {
        let transport = FakeHTTPTransport { request in
            if request.url?.query()?.contains("page=2") == true {
                return HTTPResponse(
                    statusCode: 200, headers: ["Last-Modified": "LM-2"], body: FakeHTTPTransport.page(51...53))
            }
            return Self.ok(
                FakeHTTPTransport.page(1...50),
                [
                    "Link":
                        #"<https://api.github.com/notifications?page=2>; rel="next", <https://api.github.com/notifications?page=2>; rel="last""#
                ])
        }
        let result = await client(transport).fetchNotifications(
            endpoints: github, token: aliceToken, ifModifiedSince: nil)
        guard case .updated(let threads, let lastModified, let pollInterval, let scopes, let truncated) = result else {
            Issue.record("unexpected result \(result)")
            return
        }
        #expect(threads.count == 53)
        #expect(lastModified == "LM-1")
        #expect(pollInterval == 60)
        #expect(scopes.allowsNotifications)
        #expect(!truncated)
    }

    /// 次ページの URL は `Link` のものをそのまま使い、こちらで組み立て直さない（`participating` などのクエリを保つ）
    @Test func followsTheNextLinkAsIs() async throws {
        let endpoints = try #require(APIEndpoints(host: "acme.ghe.com"))
        // クエリの並びと `after` が 1 ページ目と違うので、1 ページ目の URL から組み立て直すと一致しない
        let next = "https://api.acme.ghe.com/notifications?participating=true&all=false&per_page=50&page=2&after=c2"
        let transport = FakeHTTPTransport { request in
            if request.url?.absoluteString == next {
                return Self.ok(FakeHTTPTransport.page(3...3))
            }
            return Self.ok(FakeHTTPTransport.page(1...2), ["Link": "<\(next)>; rel=\"next\""])
        }
        let result = await client(transport).fetchNotifications(
            endpoints: endpoints, token: aliceToken, ifModifiedSince: nil, participating: true)
        #expect(transport.requests.map { $0.url?.absoluteString }.last == next)
        guard case .updated(let threads, _, _, _, _) = result else {
            Issue.record("unexpected result \(result)")
            return
        }
        #expect(threads.map(\.id) == ["1", "2", "3"])
    }

    /// 送り先の検査そのもの（スキーム・ポートなど）は `APIEndpointsTests.checksTheRequestURL` で確かめる
    @Test func doesNotFollowANextLinkOutsideTheAPIBase() async {
        let transport = FakeHTTPTransport { _ in
            Self.ok(
                FakeHTTPTransport.page(1...1), ["Link": #"<https://evil.example.com/notifications?page=2>; rel="next""#]
            )
        }
        let result = await client(transport).fetchNotifications(
            endpoints: github, token: aliceToken, ifModifiedSince: nil)
        #expect(result == .failed(.rejectedURL))
        #expect(transport.requests.count == 1)
    }

    @Test func dropsThreadsRepeatedAcrossPages() async {
        let transport = FakeHTTPTransport { request in
            if request.url?.query()?.contains("page=2") == true {
                return Self.ok(FakeHTTPTransport.page(3...5))
            }
            return Self.ok(
                FakeHTTPTransport.page(1...3), ["Link": #"<https://api.github.com/notifications?page=2>; rel="next""#])
        }
        let result = await client(transport).fetchNotifications(
            endpoints: github, token: aliceToken, ifModifiedSince: nil)
        if case .updated(let threads, _, _, _, _) = result {
            #expect(threads.map(\.id) == ["1", "2", "3", "4", "5"])
        } else {
            Issue.record("unexpected result \(result)")
        }
    }

    @Test func failsWhenALaterPageFails() async {
        let transport = FakeHTTPTransport { request throws(TransportError) in
            if request.url?.query()?.contains("page=2") == true {
                throw .network(code: URLError.Code.timedOut.rawValue)
            }
            return Self.ok(
                FakeHTTPTransport.page(1...1), ["Link": #"<https://api.github.com/notifications?page=2>; rel="next""#])
        }
        let result = await client(transport).fetchNotifications(
            endpoints: github, token: aliceToken, ifModifiedSince: nil)
        #expect(result == .failed(.network(code: URLError.Code.timedOut.rawValue)))
    }

    @Test(arguments: [
        (401, [String: String](), NotificationsFetchResult.unauthorized),
        (
            403, ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1791461400"],
            .rateLimited(retryAt: Date(timeIntervalSince1970: 1_791_461_400))
        ),
        (403, ["Retry-After": "300"], .rateLimited(retryAt: Date(timeIntervalSince1970: 1_791_461_100))),
        (403, ["X-RateLimit-Remaining": "4999"], .forbidden(scopes: OAuthScopes(header: nil))),
        (403, ["X-OAuth-Scopes": "gist"], .forbidden(scopes: OAuthScopes(header: "gist"))),
        (429, ["Retry-After": "600"], .rateLimited(retryAt: Date(timeIntervalSince1970: 1_791_461_400))),
        (429, [:], .rateLimited(retryAt: nil)),
        (422, [:], .invalidRequest),
        (302, ["Location": "https://evil.example.com/"], .failed(.redirect)),
        (304, [:], .failed(.unexpectedStatus(304))),
        (500, [:], .failed(.unexpectedStatus(500))),
    ])
    func classifiesStatusCodes(_ status: Int, _ headers: [String: String], _ expected: NotificationsFetchResult) async {
        let transport = FakeHTTPTransport { _ in
            HTTPResponse(statusCode: status, headers: headers, body: Data(#"{"message": "test-error-body"}"#.utf8))
        }
        // If-Modified-Since を付けていないので、304 は想定外の状態コードになる
        let result = await client(transport).fetchNotifications(
            endpoints: github, token: aliceToken, ifModifiedSince: nil)
        #expect(result == expected)
    }

    /// 待ち時間のヘッダーが無い二次レート制限の 403 は、スコープが揃っていてもレート制限にする（拒否にしない）
    @Test(arguments: [
        "You have exceeded a secondary rate limit. Please wait a few minutes before you try again.",
        "You have exceeded a SECONDARY RATE LIMIT.",
    ])
    func treatsASecondaryRateLimitAsARateLimit(_ message: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["message": message])
        let transport = FakeHTTPTransport { _ in
            HTTPResponse(statusCode: 403, headers: ["X-OAuth-Scopes": "repo, read:org"], body: body)
        }
        let result = await client(transport).fetchNotifications(
            endpoints: github, token: aliceToken, ifModifiedSince: nil)
        #expect(result == .rateLimited(retryAt: nil))
    }

    /// 通信の失敗の分類は `failsWhenALaterPageFails` で確かめる
    @Test func classifiesTransportFailures() async {
        let transport = FakeHTTPTransport { _ throws(TransportError) in throw .bodyTooLarge }
        let result = await client(transport).fetchNotifications(
            endpoints: github, token: aliceToken, ifModifiedSince: nil)
        #expect(result == .failed(.bodyTooLarge))
    }

    @Test func failsOnAMalformedBody() async {
        let transport = FakeHTTPTransport { _ in Self.ok(Data(#"{"not": "an array"}"#.utf8)) }
        let result = await client(transport).fetchNotifications(
            endpoints: github, token: aliceToken, ifModifiedSince: nil)
        #expect(result == .failed(.malformedBody))
    }

    @Test(arguments: [
        ("gist, read:org, repo, workflow", true),
        ("notifications", true),
        ("gist, read:org", false),
        ("", false),
        // ヘッダーが無い（classic 系でないトークン）
        (nil, false),
    ])
    func readsScopes(_ header: String?, _ allowed: Bool) {
        #expect(OAuthScopes(header: header).allowsNotifications == allowed)
    }
}

/// 10 ページで打ち切ったかどうかのテスト。
struct NotificationPagingTests {
    private let github: APIEndpoints
    private let token: AccessToken

    init() throws {
        github = try #require(APIEndpoints(host: "github.com"))
        token = try #require(AccessToken(ghOutput: Data("test-token-alice".utf8)))
    }

    /// `lastPage` ページ目まで `rel="next"` を付け、そのページで終わる。各ページは `ids(page)` のスレッド。
    private func fetchPages(
        _ lastPage: Int, ids: @escaping @Sendable (Int) -> ClosedRange<Int> = { ($0 * 100)...($0 * 100) }
    ) async -> (result: NotificationsFetchResult, transport: FakeHTTPTransport) {
        let transport = FakeHTTPTransport { request in
            // `per_page` と取り違えないように、`page` のクエリだけを読む
            let page =
                request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems?
                .first { $0.name == "page" }?.value.flatMap { Int($0) } ?? 1
            let link =
                page < lastPage
                ? ["Link": "<https://api.github.com/notifications?page=\(page + 1)>; rel=\"next\""] : [:]
            return HTTPResponse(statusCode: 200, headers: link, body: FakeHTTPTransport.page(ids(page)))
        }
        let result = await GitHubAPIClient(transport: transport).fetchNotifications(
            endpoints: github, token: token, ifModifiedSince: nil)
        return (result, transport)
    }

    @Test func isNotTruncatedWhenTheTenthPageIsTheLast() async {
        guard case .updated(_, _, _, _, let truncated) = await fetchPages(10).result else {
            Issue.record("unexpected result")
            return
        }
        #expect(!truncated)
    }

    @Test func isTruncatedByTheNextLinkEvenWithFewerThreads() async {
        // どのページも同じスレッドを返すので、重複を除くと 1 件だけになる
        let (result, transport) = await fetchPages(11, ids: { _ in 1...1 })
        guard case .updated(let threads, _, _, _, let truncated) = result else {
            Issue.record("unexpected result")
            return
        }
        #expect(threads.count == 1)
        #expect(truncated)
        // 10 ページ目の `rel="next"` はたどらない
        #expect(transport.requests.count == 10)
    }
}
