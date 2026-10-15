import Foundation
import SwiftUI
import Testing

@testable import Mewbell

private func thread(
    id: String = "1", repository: String = "octo/app", kind: SubjectKind = .pullRequest, subjectURL: String? = nil,
    updatedAt: TimeInterval = 0, releaseTag: String? = nil
) throws -> NotificationThread {
    NotificationThread(
        id: id, reason: "subscribed", updatedAt: Date(timeIntervalSince1970: updatedAt), title: "Thread \(id)",
        kind: kind, subjectURL: subjectURL.flatMap(URL.init(string:)),
        repository: try #require(RepositoryName(fullName: repository)), subjectNumber: nil,
        details: releaseTag.map { ThreadDetails(state: nil, event: nil, releaseTag: $0) }
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
    /// 表にある値は表の名前、知らない値は `_` を空白にして先頭を大文字にする。
    @Test(arguments: [("review_requested", "Review requested"), ("approval_requested", "Approval requested")])
    func namesReasons(_ reason: String, _ text: String) {
        #expect(ThreadReason.text(reason) == text)
    }
}

struct ThreadEventTextTests {
    @Test func namesEveryEvent() {
        let names = ThreadEvent.Kind.allCases.map(ThreadEventText.name)
        #expect(Set(names).count == ThreadEvent.Kind.allCases.count)
        #expect(names.allSatisfy { !$0.isEmpty })
    }

    /// 検証を通らないログイン名は出さない。
    @Test(arguments: [
        (ThreadEvent(kind: .closed, actor: "alice"), "Closed by alice"),
        (ThreadEvent(kind: .pushedCommits, actor: nil), "Pushed commits"),
        (ThreadEvent(kind: .closed, actor: "-evil"), "Closed"),
    ])
    func describesEvents(_ event: ThreadEvent, _ text: String) {
        #expect(ThreadEventText.text(event) == text)
    }
}

struct ThreadIconTests {
    @Test func distinguishesStatesByShape() {
        let pulls = [SubjectState.open, .draft, .merged, .closed].map { ThreadIcon(kind: .pullRequest, state: $0) }
        #expect(Set(pulls.map(\.symbol)).count == pulls.count)
        let issues = [SubjectState.open, .closedCompleted, .closedNotPlanned].map {
            ThreadIcon(kind: .issue, state: $0)
        }
        #expect(Set(issues.map(\.symbol)).count == issues.count)
    }

    @Test func labelsTheKindAndState() {
        #expect(ThreadIcon(kind: .issue, state: .closedNotPlanned).label == "Issue, closed as not planned")
    }

    @Test(arguments: [(SubjectKind.pullRequest, "Pull request"), (.issue, "Issue")])
    func showsOnlyTheKindWithoutAState(_ kind: SubjectKind, _ name: String) {
        let unknown = ThreadIcon(kind: kind, state: nil)
        #expect(unknown.color == nil)
        #expect(unknown.label == name)
    }

    /// 状態が分からなくても、記号で Pull request と Issue を見分けられる
    @Test func keepsTheKindsApartWithoutAState() {
        #expect(ThreadIcon(kind: .pullRequest, state: nil).symbol != ThreadIcon(kind: .issue, state: nil).symbol)
    }

    @Test func fallsBackToTheKindWithoutAMatchingState() {
        // 種類に合わない状態は、状態が無いときと同じ
        #expect(ThreadIcon(kind: .release, state: .open) == ThreadIcon(kind: .release, state: nil))
        #expect(ThreadIcon(kind: .issue, state: .merged) == ThreadIcon(kind: .issue, state: nil))
    }
}

struct TokenStateIconTests {
    /// 状態ごとの記号・色・名前。記号と色は変えず、「止まっている」と「トークンを取れない」は名前だけで読み分ける。
    /// 記号が nil なのは取得中だけ（`ProgressView` を出す）
    @Test(arguments: [
        (TokenState.fetching, FeedPhase?.none, String?.none, Color?.none, "Getting token"),
        (.ready, .loaded(updatedAt: .distantPast), "checkmark.circle.fill", .green, "Ready"),
        (.ready, .scopeInsufficient, "exclamationmark.triangle.fill", .yellow, "Stopped"),
        (.ready, .unauthorized, "exclamationmark.triangle.fill", .yellow, "Stopped"),
        (.unavailable, nil, "exclamationmark.triangle.fill", .yellow, "No token"),
        (.disabled, nil, "pause.circle", nil, "Disabled"),
    ])
    func showsTheState(
        _ tokenState: TokenState, _ phase: FeedPhase?, _ symbol: String?, _ color: Color?, _ label: String
    ) {
        let icon = TokenStateIcon(tokenState: tokenState, phase: phase)
        #expect(icon.symbol == symbol)
        #expect(icon.color == color)
        #expect(icon.label == label)
    }

    @Test(arguments: [
        FeedPhase?.none, .loading, .loaded(updatedAt: .distantPast),
        .retrying(nextAttempt: .distantFuture, rateLimited: true),
    ])
    func isReadyUnlessStopped(_ phase: FeedPhase?) {
        #expect(TokenStateIcon(tokenState: .ready, phase: phase).label == "Ready")
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
        #expect(
            ThreadWebURL.notificationsPage(endpoints: gheCloud)?.absoluteString
                == "https://acme.ghe.com/notifications")
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

    @Test func opensTheReleasesPageWithoutATag() throws {
        #expect(
            url(try thread(kind: .release, subjectURL: "https://api.github.com/repos/octo/app/releases/123"), github)
                == "https://github.com/octo/app/releases")
    }

    @Test func opensTheReleaseOfTheTag() throws {
        let subject = "https://api.github.com/repos/openai/codex/releases/413167889"
        #expect(
            url(
                try thread(
                    repository: "openai/codex", kind: .release, subjectURL: subject,
                    releaseTag: "rust-v0.163.0-alpha.10.1"), github)
                == "https://github.com/openai/codex/releases/tag/rust-v0.163.0-alpha.10.1")
        #expect(
            url(try thread(kind: .release, releaseTag: "cli/v1.2.0"), ghes)
                == "https://ghe.example.com/octo/app/releases/tag/cli/v1.2.0")
    }

    /// `?`・`#`・`%` はパスの要素としてエスケープし、クエリやフラグメントにしない。
    @Test func escapesTheTagAsPathComponents() throws {
        let opened = try #require(
            ThreadWebURL.make(for: try thread(kind: .release, releaseTag: "v1?a#b%c"), endpoints: github))
        #expect(opened.absoluteString == "https://github.com/octo/app/releases/tag/v1%3Fa%23b%25c")
        #expect(opened.query() == nil)
        #expect(opened.fragment() == nil)
        #expect(opened.host() == "github.com")
    }

    @Test(arguments: ["", "../../settings", "v1 0", "a//b"])
    func opensTheReleasesPageForAnInvalidTag(_ tag: String) throws {
        #expect(url(try thread(kind: .release, releaseTag: tag), github) == "https://github.com/octo/app/releases")
    }

    @Test func opensTheDiscussionOfTheNumber() throws {
        #expect(
            url(
                try thread(kind: .discussion, subjectURL: "https://api.github.com/repos/octo/app/discussions/2045"),
                github)
                == "https://github.com/octo/app/discussions/2045")
        #expect(
            url(
                try thread(kind: .discussion, subjectURL: "https://api.acme.ghe.com/repos/octo/app/discussions/9"),
                gheCloud)
                == "https://acme.ghe.com/octo/app/discussions/9")
        #expect(
            url(
                try thread(
                    repository: "team/svc", kind: .discussion,
                    subjectURL: "https://ghe.example.com/api/v3/repos/team/svc/discussions/3"), ghes)
                == "https://ghe.example.com/team/svc/discussions/3")
    }

    @Test(arguments: [
        nil,
        "https://evil.example.com/repos/octo/app/discussions/9",
        "https://api.github.com/repos/other/repo/discussions/9",
        "https://api.github.com/repos/octo/app/discussions/abc",
        "https://api.github.com/repos/octo/app/discussions/123456789012345678901",
        "https://api.github.com/repos/octo/app/pulls/42",
    ])
    func opensTheDiscussionsPage(_ subjectURL: String?) throws {
        #expect(
            url(try thread(kind: .discussion, subjectURL: subjectURL), github)
                == "https://github.com/octo/app/discussions")
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
    private let ghes: APIEndpoints

    init() throws {
        github = try #require(APIEndpoints(host: "github.com"))
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
    }

    /// 番号は `subject.url` の形で決まり、`subject.type` には依らない（Release と Discussion を除く）。
    @Test func readsTheNumberFromThePullRequestURLForOtherKinds() throws {
        #expect(
            try number(
                kind: .checkSuite, subjectURL: "https://api.github.com/repos/octo/app/pulls/42", endpoints: github)
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

    @Test func readsNoNumberForADiscussion() throws {
        let subject = "https://api.github.com/repos/octo/app/discussions/2045"
        #expect(try number(kind: .discussion, subjectURL: subject, endpoints: github) == nil)
    }
}

struct ThreadReleaseIDTests {
    private let github: APIEndpoints
    private let ghes: APIEndpoints

    init() throws {
        github = try #require(APIEndpoints(host: "github.com"))
        ghes = try #require(APIEndpoints(host: "ghe.example.com"))
    }

    private func releaseID(
        repository: String = "octo/app", kind: SubjectKind = .release, subjectURL: String?, endpoints: APIEndpoints
    ) throws -> String? {
        ThreadWebURL.releaseID(
            kind: kind, subjectURL: subjectURL.flatMap(URL.init(string:)),
            repository: try #require(RepositoryName(fullName: repository)), endpoints: endpoints)
    }

    @Test func readsTheReleaseID() throws {
        #expect(
            try releaseID(subjectURL: "https://api.github.com/repos/octo/app/releases/413167889", endpoints: github)
                == "413167889")
        #expect(
            try releaseID(
                repository: "team/svc", subjectURL: "https://ghe.example.com/api/v3/repos/team/svc/releases/12",
                endpoints: ghes) == "12")
    }

    @Test(arguments: [
        nil,
        "https://evil.example.com/repos/octo/app/releases/1",
        "https://api.github.com/repos/other/repo/releases/1",
        "https://api.github.com/repos/octo/app/releases/v1.0.0",
        "https://api.github.com/repos/octo/app/releases/123456789012345678901",
        "https://api.github.com/repos/octo/app/pulls/1",
    ])
    func readsNoIDFromOtherSubjects(_ subjectURL: String?) throws {
        #expect(try releaseID(subjectURL: subjectURL, endpoints: github) == nil)
    }

    @Test(arguments: [SubjectKind.pullRequest, .discussion, .commit])
    func readsNoIDForOtherKinds(_ kind: SubjectKind) throws {
        let subject = "https://api.github.com/repos/octo/app/releases/1"
        #expect(try releaseID(kind: kind, subjectURL: subject, endpoints: github) == nil)
    }
}

struct ReleaseTagTests {
    @Test(arguments: [
        ("v1.0.0", ["v1.0.0"]), ("rust-v0.163.0-alpha.10.1", ["rust-v0.163.0-alpha.10.1"]),
        ("cli/v1.2.0", ["cli", "v1.2.0"]), ("@scope/pkg@1.14.2", ["@scope", "pkg@1.14.2"]),
        (String(repeating: "a", count: 255), [String(repeating: "a", count: 255)]),
    ])
    func acceptsTags(_ tag: String, _ components: [String]) {
        #expect(ThreadWebURL.releaseTagComponents(tag) == components)
    }

    @Test(arguments: [
        "", String(repeating: "a", count: 256), "v1 0", "v1\t0", "v1\u{7}", "..", ".", "a/../b", "a/./b", "a//b",
        "/v1", "v1/",
    ])
    func rejectsTags(_ tag: String) {
        #expect(ThreadWebURL.releaseTagComponents(tag) == nil)
    }
}
