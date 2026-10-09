import Foundation
import Testing

@testable import Mewbell

struct APIEndpointsTests {
    @Test(arguments: [
        ("github.com", "https://api.github.com", "https://github.com"),
        ("GitHub.com", "https://api.github.com", "https://github.com"),
        ("acme.ghe.com", "https://api.acme.ghe.com", "https://acme.ghe.com"),
        ("github.example.com", "https://github.example.com/api/v3", "https://github.example.com"),
    ])
    func derivesBaseURLs(_ host: String, _ api: String, _ web: String) throws {
        let endpoints = try #require(APIEndpoints(host: host))
        #expect(endpoints.apiBaseURL.absoluteString == api)
        #expect(endpoints.webBaseURL.absoluteString == web)
    }

    @Test func rejectsAnInvalidHost() {
        #expect(APIEndpoints(host: "evil host/path") == nil)
        #expect(APIEndpoints(host: "-x") == nil)
    }

    @Test(arguments: [
        ("github.com", "https://api.github.com/notifications?page=2", true),
        ("github.com", "https://API.github.com:443/notifications", true),
        ("github.com", "https://evil.example.com/notifications", false),
        ("github.com", "http://api.github.com/notifications", false),
        ("github.com", "https://api.github.com:8443/notifications", false),
        ("github.com", "https://user:pass@api.github.com/notifications", false),
        ("github.com", "https://github.com/notifications", false),
        ("acme.ghe.com", "https://api.acme.ghe.com/notifications", true),
        ("acme.ghe.com", "https://api.github.com/notifications", false),
        ("ghe.example.com", "https://ghe.example.com/api/v3/notifications", true),
        ("ghe.example.com", "https://ghe.example.com/api/v3", true),
        ("ghe.example.com", "https://ghe.example.com/other", false),
        ("ghe.example.com", "https://ghe.example.com/api/v30/notifications", false),
        ("ghe.example.com", "https://ghe.example.com/api/v3/../login", false),
        ("ghe.example.com", "https://ghe.example.com/api/v3/%2e%2e/%2E%2E/login", false),
        ("ghe.example.com", "https://ghe.example.com/api/v3/%2e/notifications", false),
        ("ghe.example.com", "https://ghe.example.com/api/v3/..%2f..%2flogin", false),
        ("ghe.example.com", "https://ghe.example.com/api/v3/..%5C..%5Clogin", false),
    ])
    func checksTheRequestURL(_ host: String, _ url: String, _ allowed: Bool) throws {
        let endpoints = try #require(APIEndpoints(host: host))
        #expect(endpoints.isAllowedRequestURL(try #require(URL(string: url))) == allowed)
    }
}

struct NotificationThreadTests {
    private static func thread(
        id: String = "1", fullName: String? = "octo/app", updatedAt: String = "2026-10-08T12:00:00Z",
        subjectURL: String? = "https://api.github.com/repos/octo/app/pulls/42"
    ) -> String {
        let repository = fullName.map { #""repository": {"full_name": "\#($0)"},"# } ?? ""
        let url = subjectURL.map { "\"\($0)\"" } ?? "null"
        return """
            {"id": "\(id)", "unread": true, "reason": "review_requested", "updated_at": "\(updatedAt)",
             \(repository)
             "subject": {"title": "Fix it", "url": \(url), "latest_comment_url": null, "type": "PullRequest"}}
            """
    }

    private func decode(_ items: [String]) -> [NotificationThread]? {
        NotificationThread.decodeList(from: Data("[\(items.joined(separator: ","))]".utf8))
    }

    @Test func decodesAThread() throws {
        let threads = try #require(decode([Self.thread()]))
        let thread = try #require(threads.first)
        #expect(thread.id == "1")
        #expect(thread.reason == "review_requested")
        #expect(thread.title == "Fix it")
        #expect(thread.kind == .pullRequest)
        #expect(thread.repository == RepositoryName(owner: "octo", name: "app"))
        #expect(thread.subjectURL?.absoluteString == "https://api.github.com/repos/octo/app/pulls/42")
        #expect(thread.updatedAt == Date(timeIntervalSince1970: 1_791_460_800))
    }

    @Test func acceptsANullSubjectURL() throws {
        let threads = try #require(decode([Self.thread(subjectURL: nil)]))
        #expect(threads.count == 1)
        #expect(threads.first?.subjectURL == nil)
    }

    @Test func skipsMalformedThreadsOnly() throws {
        let threads = try #require(
            decode([
                Self.thread(id: "1"),
                Self.thread(id: "2", fullName: nil),
                Self.thread(id: "3", fullName: "no-slash"),
                Self.thread(id: "4", fullName: "a/b/c"),
                Self.thread(id: "5", updatedAt: "yesterday"),
                Self.thread(id: "6", fullName: "octo/lib"),
            ]))
        #expect(threads.map(\.id) == ["1", "6"])
    }

    @Test func rejectsABodyThatIsNotAnArray() {
        #expect(NotificationThread.decodeList(from: Data(#"{"message": "Bad credentials"}"#.utf8)) == nil)
    }

    @Test(arguments: ["octo/app", "my-org/repo.name", "a_b/c_d"])
    func acceptsRepositoryNames(_ name: String) {
        #expect(RepositoryName(fullName: name) != nil)
    }

    @Test(arguments: ["", "/", "octo/", "/app", "octo/..", "-x/app", "octo/a b", "octo/app%2F"])
    func rejectsRepositoryNames(_ name: String) {
        #expect(RepositoryName(fullName: name) == nil)
    }
}

struct LinkHeaderTests {
    @Test func readsTheNextLink() {
        let header =
            #"<https://api.github.com/notifications?page=2>; rel="next", <https://api.github.com/notifications?page=5>; rel="last""#
        #expect(LinkHeader.nextURL(in: header)?.absoluteString == "https://api.github.com/notifications?page=2")
    }

    @Test func readsTheNextLinkInAnyOrderAndSpacing() {
        let header = #"<https://x.test/1>;rel="prev" ,  <https://x.test/3> ;  rel=next"#
        #expect(LinkHeader.nextURL(in: header)?.absoluteString == "https://x.test/3")
    }

    @Test func returnsNilWithoutANextLink() {
        #expect(LinkHeader.nextURL(in: #"<https://x.test/1>; rel="prev""#) == nil)
        #expect(LinkHeader.nextURL(in: nil) == nil)
        #expect(LinkHeader.nextURL(in: "garbage") == nil)
        #expect(LinkHeader.nextURL(in: #"https://x.test/2; rel="next""#) == nil)
    }
}
