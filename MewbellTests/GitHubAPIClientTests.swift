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
        #expect(configuration.timeoutIntervalForRequest == 30)
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
    private let bobToken: AccessToken
    private let now = Date(timeIntervalSince1970: 1_791_460_800)

    init() throws {
        github = try #require(APIEndpoints(host: "github.com"))
        ghes = try #require(APIEndpoints(host: "ghe.example.com"))
        aliceToken = try #require(AccessToken(ghOutput: Data("test-token-alice".utf8)))
        bobToken = try #require(AccessToken(ghOutput: Data("test-token-bob".utf8)))
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
        guard case .updated(let threads, let lastModified, let pollInterval, let scopes) = result else {
            Issue.record("unexpected result \(result)")
            return
        }
        #expect(threads.count == 53)
        #expect(lastModified == "LM-1")
        #expect(pollInterval == 60)
        #expect(scopes.allowsNotifications)
    }

    @Test(arguments: [
        "https://evil.example.com/notifications?page=2",
        "http://api.github.com/notifications?page=2",
        "https://api.github.com:8443/notifications?page=2",
    ])
    func doesNotFollowANextLinkOutsideTheAPIBase(_ next: String) async {
        let transport = FakeHTTPTransport { _ in
            Self.ok(FakeHTTPTransport.page(1...1), ["Link": "<\(next)>; rel=\"next\""])
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
        if case .updated(let threads, _, _, _) = result {
            #expect(threads.map(\.id) == ["1", "2", "3", "4", "5"])
        } else {
            Issue.record("unexpected result \(result)")
        }
    }

    @Test func stopsAtTheTenthPage() async {
        let transport = FakeHTTPTransport { request in
            let page = Int(request.url?.query()?.split(separator: "page=").last ?? "1") ?? 1
            return Self.ok(
                FakeHTTPTransport.page((page * 100)...(page * 100)),
                ["Link": "<https://api.github.com/notifications?page=\(page + 1)>; rel=\"next\""])
        }
        let result = await client(transport).fetchNotifications(
            endpoints: github, token: aliceToken, ifModifiedSince: nil)
        #expect(transport.requests.count == 10)
        if case .updated(let threads, _, _, _) = result {
            #expect(threads.count == 10)
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
        (403, ["X-RateLimit-Remaining": "4999"], .forbidden),
        (429, ["Retry-After": "600"], .rateLimited(retryAt: Date(timeIntervalSince1970: 1_791_461_400))),
        (429, [:], .rateLimited(retryAt: Date(timeIntervalSince1970: 1_791_460_800))),
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

    @Test func classifiesTransportFailures() async {
        for (error, expected) in [
            (TransportError.bodyTooLarge, FetchFailure.bodyTooLarge),
            (.network(code: -1009), .network(code: -1009)),
        ] {
            let transport = FakeHTTPTransport { _ throws(TransportError) in throw error }
            let result = await client(transport).fetchNotifications(
                endpoints: github, token: aliceToken, ifModifiedSince: nil)
            #expect(result == .failed(expected))
        }
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
    ])
    func readsScopes(_ header: String, _ allowed: Bool) {
        #expect(OAuthScopes(header: header).allowsNotifications == allowed)
    }

    @Test func treatsAMissingScopesHeaderAsInsufficient() {
        #expect(!OAuthScopes(header: nil).allowsNotifications)
    }

    @Test func keepsEachAccountsTokenAcrossPagesWhenFetchingConcurrently() async throws {
        let transport = FakeHTTPTransport { request in
            if request.url?.query()?.contains("page=2") == true {
                return Self.ok(FakeHTTPTransport.page(2...2), [:])
            }
            return Self.ok(
                FakeHTTPTransport.page(1...1), ["Link": #"<https://api.github.com/notifications?page=2>; rel="next""#])
        }
        let client = client(transport)
        async let alice = client.fetchNotifications(endpoints: github, token: aliceToken, ifModifiedSince: nil)
        async let bob = client.fetchNotifications(endpoints: github, token: bobToken, ifModifiedSince: nil)
        _ = await (alice, bob)
        let tokens = transport.requests.compactMap { $0.value(forHTTPHeaderField: "Authorization") }
        #expect(tokens.filter { $0 == "Bearer test-token-alice" }.count == 2)
        #expect(tokens.filter { $0 == "Bearer test-token-bob" }.count == 2)
        #expect(tokens.count == 4)
    }

    @Test func doesNotLeakTheTokenOrTheErrorBodyInResults() async {
        let transport = FakeHTTPTransport { _ in
            HTTPResponse(statusCode: 401, body: Data(#"{"message": "test-error-body"}"#.utf8))
        }
        let client = client(transport)
        let results = [
            await client.fetchNotifications(endpoints: github, token: aliceToken, ifModifiedSince: nil),
            .failed(.unexpectedStatus(500)),
        ]
        for result in results {
            for text in [String(describing: result), String(reflecting: result)] {
                #expect(!text.contains("test-token-alice"))
                #expect(!text.contains("test-error-body"))
            }
        }
    }
}
