import Foundation
import SwiftUI
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
    @Test(arguments: [
        (TokenState.fetching, FeedPhase?.none, "Getting token"),
        (.ready, .loaded(updatedAt: .distantPast), "Ready"),
        (.ready, .scopeInsufficient, "Stopped"),
        (.ready, .unauthorized, "Stopped"),
        (.unavailable, nil, "No token"),
    ])
    func namesTheState(_ tokenState: TokenState, _ phase: FeedPhase?, _ label: String) {
        #expect(TokenStateIcon(tokenState: tokenState, phase: phase).label == label)
    }

    /// 同じ記号と色でも、名前で読み分けられる
    @Test func keepsStoppedAndNoTokenApartByName() {
        let stopped = TokenStateIcon(tokenState: .ready, phase: .unauthorized)
        let noToken = TokenStateIcon(tokenState: .unavailable, phase: nil)
        #expect(stopped.symbol == noToken.symbol)
        #expect(stopped.color == noToken.color)
        #expect(stopped.label != noToken.label)
    }

    /// 取得中だけ記号が無い（`ProgressView` を出す）。取得中は取得の状態にかかわらない
    @Test(arguments: [FeedPhase?.none, .loaded(updatedAt: .distantPast), .unauthorized])
    func showsProgressOnlyWhileFetching(_ phase: FeedPhase?) {
        #expect(TokenStateIcon(tokenState: .fetching, phase: phase).symbol == nil)
        #expect(TokenStateIcon(tokenState: .ready, phase: phase).symbol != nil)
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
}
