import Foundation
import Testing

@testable import Mewbell

/// `GitHubAPIClient.fetchDetails` のリクエストと結果（github-api「スレッドのイベントの取得のリクエスト」）。
struct ThreadDetailsRequestTests {
    private let now = Date(timeIntervalSince1970: 1_791_460_800)
    private let token: AccessToken
    private let issue = TimelineJSON.issue(createdAt: "2026-10-08T10:00:00Z")
    private let comment = TimelineJSON.page([TimelineJSON.commented(at: "2026-10-08T11:59:40Z", by: "bob")])

    init() throws {
        token = try #require(AccessToken(ghOutput: Data("test-token-alice".utf8)))
    }

    private func thread(
        host: String = "github.com", repository: String = "octo/app", subjectURL: String?, type: String = "Issue"
    ) throws -> (NotificationThread, APIEndpoints) {
        let endpoints = try #require(APIEndpoints(host: host))
        let json = FakeHTTPTransport.threadJSON(
            id: "1", repository: repository, updatedAt: "2026-10-08T12:00:00Z", subjectURL: subjectURL, type: type)
        let thread = try #require(
            NotificationThread.decodeList(from: Data("[\(json)]".utf8), endpoints: endpoints)?.first)
        return (thread, endpoints)
    }

    /// パスで応答を振り分けるトランスポート（Timeline は `page` の値ごと）。
    private func transport(
        issue: HTTPResponse, timeline: @escaping @Sendable (Int) -> HTTPResponse
    ) -> FakeHTTPTransport {
        FakeHTTPTransport { request in
            guard let url = request.url else { return HTTPResponse(statusCode: 500) }
            guard url.path().hasSuffix("/timeline") else { return issue }
            let page =
                URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .first { $0.name == "page" }?.value.flatMap { Int($0) } ?? 1
            return timeline(page)
        }
    }

    private func fetch(_ thread: NotificationThread, _ endpoints: APIEndpoints, _ transport: FakeHTTPTransport)
        async -> ThreadDetailsFetchResult
    {
        let now = now
        return await GitHubAPIClient(transport: transport, now: { now })
            .fetchDetails(for: thread, endpoints: endpoints, token: token)
    }

    private static func ok(_ body: Data, link: String? = nil) -> HTTPResponse {
        HTTPResponse(statusCode: 200, headers: link.map { ["Link": $0] } ?? [:], body: body)
    }

    @Test func fetchesTheIssueAndItsTimeline() async throws {
        let (thread, endpoints) = try thread(subjectURL: "https://api.github.com/repos/octo/app/issues/7")
        let transport = transport(issue: Self.ok(issue)) { _ in Self.ok(comment) }
        let result = await fetch(thread, endpoints, transport)
        #expect(result == .found(ThreadDetails(state: .open, event: ThreadEvent(kind: .commented, actor: "bob"))))
        #expect(
            transport.requests.map { $0.url?.absoluteString } == [
                "https://api.github.com/repos/octo/app/issues/7",
                "https://api.github.com/repos/octo/app/issues/7/timeline?per_page=100",
            ])
        #expect(transport.requests.allSatisfy { $0.httpMethod == "GET" })
        #expect(
            transport.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer test-token-alice" }
        )
    }

    @Test(arguments: [
        ("ghe.example.com", "https://ghe.example.com/api/v3/repos/team/svc/pulls/42", "https://ghe.example.com/api/v3"),
        ("acme.ghe.com", "https://api.acme.ghe.com/repos/team/svc/pulls/42", "https://api.acme.ghe.com"),
    ])
    func usesTheIssuesPathForPullRequests(_ host: String, _ subjectURL: String, _ base: String) async throws {
        let (thread, endpoints) = try thread(
            host: host, repository: "team/svc", subjectURL: subjectURL, type: "PullRequest")
        let transport = transport(issue: Self.ok(issue)) { _ in Self.ok(comment) }
        _ = await fetch(thread, endpoints, transport)
        #expect(
            transport.requests.map { $0.url?.absoluteString } == [
                "\(base)/repos/team/svc/issues/42", "\(base)/repos/team/svc/issues/42/timeline?per_page=100",
            ])
    }

    @Test func buildsTheURLFromTheValidatedRepository() async throws {
        let (thread, endpoints) = try thread(subjectURL: "https://api.github.com/repos/OCTO/App/issues/7")
        let transport = transport(issue: Self.ok(issue)) { _ in Self.ok(comment) }
        _ = await fetch(thread, endpoints, transport)
        #expect(transport.requests.first?.url?.absoluteString == "https://api.github.com/repos/octo/app/issues/7")
    }

    @Test(arguments: [
        (nil as String?, "Release"), ("https://evil.example.com/repos/octo/app/issues/7", "Issue"),
        ("https://api.github.com/repos/octo/app/commits/abcdef1", "Commit"),
        ("https://api.github.com/repos/other/app/issues/7", "Issue"),
    ])
    func sendsNothingWithoutANumber(_ subjectURL: String?, _ type: String) async throws {
        let (thread, endpoints) = try thread(subjectURL: subjectURL, type: type)
        let transport = transport(issue: Self.ok(issue)) { _ in Self.ok(comment) }
        #expect(await fetch(thread, endpoints, transport) == .unavailable)
        #expect(transport.requests.isEmpty)
    }

    @Test func fetchesTheLastPage() async throws {
        let (thread, endpoints) = try thread(subjectURL: "https://api.github.com/repos/octo/app/issues/7")
        let last = #"<https://api.github.com/repositories/1/issues/7/timeline?per_page=100&page=5>; rel="last""#
        // 最後のページが近さの幅の始まりより前（11:00）まで届いているので、前のページは取らない
        let lastPage = TimelineJSON.page([
            TimelineJSON.event("labeled", at: "2026-10-08T11:00:00Z"),
            TimelineJSON.commented(at: "2026-10-08T11:59:40Z", by: "bob"),
        ])
        let transport = transport(issue: Self.ok(issue)) { page in
            page == 1 ? Self.ok(TimelineJSON.page([]), link: last) : Self.ok(lastPage)
        }
        let result = await fetch(thread, endpoints, transport)
        #expect(result == .found(ThreadDetails(state: .open, event: ThreadEvent(kind: .commented, actor: "bob"))))
        #expect(
            transport.requests.map { $0.url?.absoluteString }.last
                == "https://api.github.com/repositories/1/issues/7/timeline?per_page=100&page=5")
        #expect(transport.requests.count == 3)
    }

    @Test func fetchesThePageBeforeTheLastWithoutACandidate() async throws {
        let (thread, endpoints) = try thread(subjectURL: "https://api.github.com/repos/octo/app/issues/7")
        let last = #"<https://api.github.com/repositories/1/issues/7/timeline?per_page=100&page=5>; rel="last""#
        let transport = transport(issue: Self.ok(issue)) { page in
            switch page {
            case 1: Self.ok(TimelineJSON.page([]), link: last)
            case 4: Self.ok(comment)
            default: Self.ok(TimelineJSON.page([TimelineJSON.event("labeled", at: "2026-10-08T11:59:50Z")]))
            }
        }
        let result = await fetch(thread, endpoints, transport)
        #expect(result == .found(ThreadDetails(state: .open, event: ThreadEvent(kind: .commented, actor: "bob"))))
        #expect(
            transport.requests.map { $0.url?.absoluteString }.last
                == "https://api.github.com/repos/octo/app/issues/7/timeline?per_page=100&page=4")
        #expect(transport.requests.count == 4)
    }

    @Test func looksForACloserEventOnThePageBeforeTheLast() async throws {
        let (thread, endpoints) = try thread(subjectURL: "https://api.github.com/repos/octo/app/issues/7")
        let last = #"<https://api.github.com/repositories/1/issues/7/timeline?per_page=100&page=5>; rel="last""#
        let transport = transport(issue: Self.ok(issue)) { page in
            switch page {
            case 1: Self.ok(TimelineJSON.page([]), link: last)
            case 4:
                Self.ok(TimelineJSON.page([TimelineJSON.reviewed("approved", at: "2026-10-08T11:59:59Z", by: "carol")]))
            default: Self.ok(TimelineJSON.page([TimelineJSON.commented(at: "2026-10-08T11:57:10Z", by: "bob")]))
            }
        }
        let result = await fetch(thread, endpoints, transport)
        #expect(result == .found(ThreadDetails(state: .open, event: ThreadEvent(kind: .approved, actor: "carol"))))
        #expect(transport.requests.count == 4)
    }

    @Test func doesNotTrustOldCommitDatesOnTheLastPage() async throws {
        let (thread, endpoints) = try thread(subjectURL: "https://api.github.com/repos/octo/app/issues/7")
        let last = #"<https://api.github.com/repositories/1/issues/7/timeline?per_page=100&page=5>; rel="last""#
        let transport = transport(issue: Self.ok(issue)) { page in
            switch page {
            case 1: Self.ok(TimelineJSON.page([]), link: last)
            case 4: Self.ok(TimelineJSON.page([TimelineJSON.commented(at: "2026-10-08T11:59:30Z", by: "bob")]))
            // 古い日付のまま後から push したコミットだけ
            default: Self.ok(TimelineJSON.page([TimelineJSON.committed(at: "2026-10-01T09:00:00Z")]))
            }
        }
        let result = await fetch(thread, endpoints, transport)
        #expect(result == .found(ThreadDetails(state: .open, event: ThreadEvent(kind: .commented, actor: "bob"))))
        #expect(transport.requests.count == 4)
    }

    @Test func doesNotRefetchTheFirstPage() async throws {
        let (thread, endpoints) = try thread(subjectURL: "https://api.github.com/repos/octo/app/issues/7")
        let last = #"<https://api.github.com/repositories/1/issues/7/timeline?per_page=100&page=2>; rel="last""#
        let transport = transport(issue: Self.ok(issue)) { [comment] page in
            page == 1 ? Self.ok(comment, link: last) : Self.ok(TimelineJSON.page([]))
        }
        let result = await fetch(thread, endpoints, transport)
        // 最後のページに候補が無いので、取ってある 1 ページ目の候補を使う
        #expect(result == .found(ThreadDetails(state: .open, event: ThreadEvent(kind: .commented, actor: "bob"))))
        #expect(transport.requests.count == 3)
    }

    @Test(arguments: [
        "https://evil.example.com/timeline?page=5", "http://api.github.com/repos/octo/app/issues/7/timeline?page=5",
    ])
    func refusesALastPageOutsideTheAPIBase(_ lastURL: String) async throws {
        let (thread, endpoints) = try thread(subjectURL: "https://api.github.com/repos/octo/app/issues/7")
        let transport = transport(issue: Self.ok(issue)) { _ in
            Self.ok(TimelineJSON.page([]), link: "<\(lastURL)>; rel=\"last\"")
        }
        #expect(await fetch(thread, endpoints, transport) == .failed(.rejectedURL))
        #expect(transport.requests.count == 2)
        #expect(transport.requests.allSatisfy { $0.url?.host() == "api.github.com" && $0.url?.scheme == "https" })
    }

    @Test(arguments: [404, 410, 422])
    func treatsAMissingIssueAsUnavailable(_ status: Int) async throws {
        let (thread, endpoints) = try thread(subjectURL: "https://api.github.com/repos/octo/app/issues/7")
        let transport = transport(issue: HTTPResponse(statusCode: status)) { _ in Self.ok(comment) }
        #expect(await fetch(thread, endpoints, transport) == .unavailable)
        #expect(transport.requests.count == 1)
    }

    @Test func treatsAPlainForbiddenAsUnavailable() async throws {
        let (thread, endpoints) = try thread(subjectURL: "https://api.github.com/repos/octo/app/issues/7")
        let transport = transport(issue: HTTPResponse(statusCode: 403)) { _ in Self.ok(comment) }
        #expect(await fetch(thread, endpoints, transport) == .unavailable)
    }

    @Test func keepsTheStateWhenTheTimelineIsMissing() async throws {
        let (thread, endpoints) = try thread(subjectURL: "https://api.github.com/repos/octo/app/issues/7")
        let transport = transport(issue: Self.ok(issue)) { _ in HTTPResponse(statusCode: 404) }
        #expect(await fetch(thread, endpoints, transport) == .found(ThreadDetails(state: .open, event: nil)))
    }

    @Test func unauthorized() async throws {
        let (thread, endpoints) = try thread(subjectURL: "https://api.github.com/repos/octo/app/issues/7")
        let transport = transport(issue: Self.ok(issue)) { _ in HTTPResponse(statusCode: 401) }
        #expect(await fetch(thread, endpoints, transport) == .unauthorized)
    }

    @Test func rateLimited() async throws {
        let (thread, endpoints) = try thread(subjectURL: "https://api.github.com/repos/octo/app/issues/7")
        let reset = now.addingTimeInterval(600)
        let forbidden = HTTPResponse(
            statusCode: 403,
            headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": String(Int(reset.timeIntervalSince1970))])
        #expect(
            await fetch(thread, endpoints, transport(issue: Self.ok(issue)) { _ in forbidden })
                == .rateLimited(retryAt: reset))
        let tooMany = HTTPResponse(statusCode: 429, headers: ["Retry-After": "120"])
        #expect(
            await fetch(thread, endpoints, transport(issue: tooMany) { _ in Self.ok(comment) })
                == .rateLimited(retryAt: now.addingTimeInterval(120)))
    }

    @Test func temporaryFailures() async throws {
        let (thread, endpoints) = try thread(subjectURL: "https://api.github.com/repos/octo/app/issues/7")
        #expect(
            await fetch(thread, endpoints, transport(issue: HTTPResponse(statusCode: 502)) { _ in Self.ok(comment) })
                == .failed(.unexpectedStatus(502)))
        #expect(
            await fetch(
                thread, endpoints,
                transport(issue: HTTPResponse(statusCode: 302, headers: ["Location": "https://evil.example.com/"])) {
                    _ in Self.ok(comment)
                }) == .failed(.redirect))
        #expect(
            await fetch(thread, endpoints, transport(issue: Self.ok(Data("{}".utf8))) { _ in Self.ok(comment) })
                == .failed(.malformedBody))
        #expect(
            await fetch(thread, endpoints, transport(issue: Self.ok(issue)) { _ in Self.ok(Data("{}".utf8)) })
                == .failed(.malformedBody))
        let offline = FakeHTTPTransport { _ throws(TransportError) in
            throw .network(code: URLError.Code.notConnectedToInternet.rawValue)
        }
        #expect(
            await fetch(thread, endpoints, offline)
                == .failed(.network(code: URLError.Code.notConnectedToInternet.rawValue)))
    }
}
