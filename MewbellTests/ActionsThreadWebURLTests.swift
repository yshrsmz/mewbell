import Foundation
import Testing

@testable import Mewbell

/// 種類が WorkflowRun と CheckSuite のスレッドを開く URL（ui「通知のスレッドを開く」）。
struct ActionsThreadWebURLTests {
    private let github: APIEndpoints
    private let ghes: APIEndpoints

    init() throws {
        github = try #require(APIEndpoints(host: "github.com"))
        ghes = try #require(APIEndpoints(host: "ghe.example.com"))
    }

    private func thread(
        repository: String = "octo/app", kind: SubjectKind, subjectURL: String? = nil,
        title: String = "bob requested your review to deploy to an environment", workflowRunID: String? = nil
    ) throws -> NotificationThread {
        NotificationThread(
            id: "1", reason: "subscribed", updatedAt: Date(timeIntervalSince1970: 0), title: title, kind: kind,
            subjectURL: subjectURL.flatMap(URL.init(string:)),
            repository: try #require(RepositoryName(fullName: repository)), detailsSubject: nil,
            details: workflowRunID.map { ThreadDetails(state: nil, event: nil, resource: .workflowRun(id: $0)) })
    }

    private func url(_ thread: NotificationThread, _ endpoints: APIEndpoints) -> String? {
        ThreadWebURL.make(for: thread, endpoints: endpoints)?.absoluteString
    }

    @Test func opensTheRunOfActionsThreads() throws {
        #expect(
            url(try thread(kind: .workflowRun, workflowRunID: "38692691414"), github)
                == "https://github.com/octo/app/actions/runs/38692691414")
        #expect(
            url(
                try thread(kind: .checkSuite, title: "CI workflow run failed for main branch", workflowRunID: "201"),
                github)
                == "https://github.com/octo/app/actions/runs/201")
        #expect(
            url(try thread(repository: "team/svc", kind: .workflowRun, workflowRunID: "1"), ghes)
                == "https://ghe.example.com/team/svc/actions/runs/1")
    }

    @Test func opensTheWaitingRunsWithoutARun() throws {
        #expect(url(try thread(kind: .workflowRun), github) == "https://github.com/octo/app/actions?query=is:waiting")
        // 検証を通らない run の ID は使わない
        #expect(
            url(try thread(kind: .workflowRun, workflowRunID: "../1"), github)
                == "https://github.com/octo/app/actions?query=is:waiting")
    }

    @Test(arguments: [
        (
            "Build and test workflow run, Attempt #2 failed for feat/a+b branch",
            "query=workflow:%22Build%20and%20test%22%20is:failure%20branch:feat/a%2Bb"
        ),
        ("CI workflow run failed at startup for main branch", "query=workflow:%22CI%22%20is:failure%20branch:main"),
        ("CI workflow run cancelled for main branch", "query=workflow:%22CI%22%20is:cancelled%20branch:main"),
        ("CI workflow run skipped for main branch", "query=workflow:%22CI%22%20is:skipped%20branch:main"),
        ("CI workflow run succeeded for main branch", "query=workflow:%22CI%22%20is:success%20branch:main"),
        // 名前に `"` を含むワークフローは名前で絞らない。`&` や `#` はクエリの値の中に閉じる
        (#"Say "hi" workflow run failed for main branch"#, "query=is:failure%20branch:main"),
        ("CI workflow run failed for a&b#c branch", "query=workflow:%22CI%22%20is:failure%20branch:a%26b%23c"),
        // `"` や空白を含むブランチでは絞らない
        (#"CI workflow run failed for fix/"q" branch"#, "query=workflow:%22CI%22%20is:failure"),
        ("CI workflow run failed for a b branch", "query=workflow:%22CI%22%20is:failure"),
    ])
    func opensTheFilteredRunsWithoutARun(_ title: String, _ query: String) throws {
        let opened = try #require(
            ThreadWebURL.make(for: try thread(kind: .checkSuite, title: title), endpoints: github))
        #expect(opened.absoluteString == "https://github.com/octo/app/actions?\(query)")
        #expect(opened.fragment() == nil)
        #expect(opened.host() == "github.com")
    }

    @Test func opensTheActionsPageForAnUnreadableCheckSuite() throws {
        #expect(
            url(try thread(kind: .checkSuite, title: "Something happened"), github)
                == "https://github.com/octo/app/actions")
    }

    /// `subject.url` が Pull request を指すときは、今までどおりそのページを開く。
    @Test func opensThePullRequestOfAnActionsThread() throws {
        #expect(
            url(
                try thread(
                    kind: .checkSuite, subjectURL: "https://api.github.com/repos/octo/app/pulls/42",
                    title: "CI workflow run failed for main branch"), github)
                == "https://github.com/octo/app/pull/42")
    }
}
