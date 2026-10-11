import Foundation
import Testing

@testable import Mewbell

private func thread(
    id: String = "1", repository: String = "octo/app", kind: SubjectKind = .pullRequest, subjectURL: String? = nil,
    updatedAt: TimeInterval = 0
) throws -> NotificationThread {
    NotificationThread(
        id: id, reason: "subscribed", updatedAt: Date(timeIntervalSince1970: updatedAt), title: "Thread \(id)",
        kind: kind, subjectURL: subjectURL.flatMap(URL.init(string:)),
        repository: try #require(RepositoryName(fullName: repository)), subjectNumber: nil
    )
}

struct RepositoryGroupTests {
    @Test func ordersRepositoriesAndThreadsByTheNewestUpdate() throws {
        let groups = RepositoryGroup.groups(from: [
            try thread(id: "1", repository: "octo/app", updatedAt: 100),
            try thread(id: "2", repository: "octo/lib", updatedAt: 300),
            try thread(id: "3", repository: "octo/app", updatedAt: 200),
            try thread(id: "4", repository: "acme/web", updatedAt: 50),
        ])
        #expect(groups.map(\.id) == ["octo/lib", "octo/app", "acme/web"])
        #expect(groups[1].threads.map(\.id) == ["3", "1"])
    }

    @Test func returnsNoGroupsForNoThreads() {
        #expect(RepositoryGroup.groups(from: []).isEmpty)
    }
}

struct ThreadReasonTests {
    @Test(arguments: [
        ("review_requested", "Review requested"),
        ("mention", "Mentioned"),
        ("approval_requested", "Approval requested"),
        ("", ""),
    ])
    func namesReasons(_ reason: String, _ text: String) {
        #expect(ThreadReason.text(reason) == text)
    }
}

struct ThreadWebURLTests {
    private let github: APIEndpoints
    private let gheCloud: APIEndpoints
    private let ghes: APIEndpoints

    init() throws {
        github = try #require(APIEndpoints(host: "github.com"))
        gheCloud = try #require(APIEndpoints(host: "acme.ghe.com"))
        ghes = try #require(APIEndpoints(host: "ghe.example.com"))
    }

    private func url(_ thread: NotificationThread, _ endpoints: APIEndpoints) -> String? {
        ThreadWebURL.make(for: thread, endpoints: endpoints)?.absoluteString
    }

    @Test func opensTheWebNotificationsPageOfTheHost() {
        #expect(ThreadWebURL.notificationsPage(endpoints: github)?.absoluteString == "https://github.com/notifications")
        #expect(
            ThreadWebURL.notificationsPage(endpoints: gheCloud)?.absoluteString
                == "https://acme.ghe.com/notifications")
        #expect(
            ThreadWebURL.notificationsPage(endpoints: ghes)?.absoluteString == "https://ghe.example.com/notifications")
        for endpoints in [github, gheCloud, ghes] {
            let url = ThreadWebURL.notificationsPage(endpoints: endpoints)
            #expect(url?.query == nil)
            #expect(url?.host == endpoints.host)
        }
    }

    @Test func opensPullRequestsIssuesAndCommits() throws {
        #expect(
            url(try thread(subjectURL: "https://api.github.com/repos/octo/app/pulls/42"), github)
                == "https://github.com/octo/app/pull/42")
        #expect(
            url(try thread(kind: .issue, subjectURL: "https://api.acme.ghe.com/repos/octo/app/issues/7"), gheCloud)
                == "https://acme.ghe.com/octo/app/issues/7")
        #expect(
            url(
                try thread(
                    repository: "team/svc", kind: .issue,
                    subjectURL: "https://ghe.example.com/api/v3/repos/team/svc/issues/7"), ghes)
                == "https://ghe.example.com/team/svc/issues/7")
        #expect(
            url(
                try thread(kind: .commit, subjectURL: "https://api.github.com/repos/Octo/App/commits/0123abcdef"),
                github)
                == "https://github.com/octo/app/commit/0123abcdef")
    }

    @Test func opensReleasesAndDiscussionsPages() throws {
        #expect(
            url(try thread(kind: .release, subjectURL: "https://api.github.com/repos/octo/app/releases/123"), github)
                == "https://github.com/octo/app/releases")
        #expect(url(try thread(kind: .discussion), github) == "https://github.com/octo/app/discussions")
    }

    @Test(arguments: [
        nil,
        "https://evil.example.com/repos/octo/app/pulls/42",
        "http://api.github.com/repos/octo/app/pulls/42",
        "https://api.github.com/repos/other/app/pulls/42",
        "https://api.github.com/repos/octo/app/pulls/42abc",
        "https://api.github.com/repos/octo/app/commits/not-a-sha",
        "https://api.github.com/repos/octo/app/pulls/42/extra",
        "https://api.github.com/repos/octo/app/check-suites/1",
        "https://github.com/repos/octo/app/pulls/42",
    ])
    func fallsBackToTheRepositoryPage(_ subjectURL: String?) throws {
        #expect(url(try thread(subjectURL: subjectURL), github) == "https://github.com/octo/app")
    }

    @Test func alwaysPointsAtTheAccountHostOverHTTPS() throws {
        let endpoints = [github, gheCloud, ghes]
        let subjects: [String?] = [
            nil, "https://evil.example.com/repos/octo/app/pulls/1", "https://api.github.com/repos/octo/app/issues/1",
        ]
        for endpoints in endpoints {
            for subject in subjects {
                let opened = try #require(ThreadWebURL.make(for: try thread(subjectURL: subject), endpoints: endpoints))
                #expect(opened.scheme == "https")
                #expect(opened.host() == endpoints.host)
            }
        }
    }
}

struct ThreadSubjectNumberTests {
    private let github: APIEndpoints
    private let gheCloud: APIEndpoints
    private let ghes: APIEndpoints

    init() throws {
        github = try #require(APIEndpoints(host: "github.com"))
        gheCloud = try #require(APIEndpoints(host: "acme.ghe.com"))
        ghes = try #require(APIEndpoints(host: "ghe.example.com"))
    }

    /// スレッドの部品から番号を求める（スレッドを作る前に呼ぶ形）。
    private func number(
        repository: String = "octo/app", kind: SubjectKind = .pullRequest, subjectURL: String?,
        endpoints: APIEndpoints
    ) throws -> String? {
        ThreadWebURL.subjectNumber(
            kind: kind, subjectURL: subjectURL.flatMap(URL.init(string:)),
            repository: try #require(RepositoryName(fullName: repository)), endpoints: endpoints)
    }

    @Test func readsPullRequestAndIssueNumbers() throws {
        #expect(try number(subjectURL: "https://api.github.com/repos/octo/app/pulls/42", endpoints: github) == "42")
        #expect(
            try number(
                repository: "team/svc", kind: .issue,
                subjectURL: "https://ghe.example.com/api/v3/repos/team/svc/issues/7", endpoints: ghes) == "7")
        #expect(
            try number(
                repository: "acme/web", subjectURL: "https://api.acme.ghe.com/repos/acme/web/pulls/3",
                endpoints: gheCloud) == "3")
    }

    /// 番号は `subject.url` の形で決まり、`subject.type` には依らない（Release と Discussion を除く）。
    @Test(arguments: [SubjectKind.issue, .commit, .checkSuite])
    func readsTheNumberFromThePullRequestURLForOtherKinds(_ kind: SubjectKind) throws {
        #expect(
            try number(kind: kind, subjectURL: "https://api.github.com/repos/octo/app/pulls/42", endpoints: github)
                == "42")
    }

    @Test(arguments: [
        nil,
        "https://evil.example.com/repos/octo/app/pulls/42",
        "https://api.github.com/repos/other/app/pulls/42",
        "https://api.github.com/repos/octo/app/pulls/abc",
        "https://api.github.com/repos/octo/app/commits/0123abcdef",
    ])
    func readsNoNumberFromOtherSubjects(_ subjectURL: String?) throws {
        #expect(try number(subjectURL: subjectURL, endpoints: github) == nil)
    }

    @Test(arguments: [SubjectKind.release, .discussion])
    func readsNoNumberForOtherKinds(_ kind: SubjectKind) throws {
        let subject = "https://api.github.com/repos/octo/app/pulls/42"
        #expect(try number(kind: kind, subjectURL: subject, endpoints: github) == nil)
    }
}
