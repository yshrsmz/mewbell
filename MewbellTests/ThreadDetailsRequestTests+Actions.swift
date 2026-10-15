import Foundation
import Testing

@testable import Mewbell

// WorkflowRun と CheckSuite のスレッドの `GitHubAPIClient.fetchDetails` のリクエストと結果
// （github-api「ワークフローの実行の検索のリクエスト」）。スレッドの `updated_at` は 2026-10-08T12:00:00Z
extension ThreadDetailsRequestTests {
    private func approvalThread(host: String = "github.com", repository: String = "octo/app") throws
        -> (NotificationThread, APIEndpoints)
    {
        try thread(
            host: host, repository: repository, subjectURL: nil, type: "WorkflowRun",
            title: "bob requested your review to deploy to an environment")
    }

    private func checkSuiteThread(title: String = "CI workflow run failed for main branch") throws
        -> (NotificationThread, APIEndpoints)
    {
        try thread(subjectURL: nil, type: "CheckSuite", title: title)
    }

    /// run の一覧の 1 件（ID、ワークフロー名、`updated_at`、結果）。
    private struct Run {
        let id: String
        let name: String
        let updatedAt: String
        let conclusion: String

        init(_ id: String, _ name: String, _ updatedAt: String, _ conclusion: String = "failure") {
            (self.id, self.name, self.updatedAt, self.conclusion) = (id, name, updatedAt, conclusion)
        }
    }

    /// run の一覧の `200`。
    private static func runs(_ runs: [Run], totalCount: Int? = nil) -> HTTPResponse {
        let items = runs.map { run in
            #"{"id": \#(run.id), "name": "\#(run.name)", "display_title": "Fix it", "updated_at": "\#(run.updatedAt)", "#
                + #""conclusion": "\#(run.conclusion)", "#
                + #""html_url": "https://evil.example.com/octo/app/actions/runs/\#(run.id)"}"#
        }
        let body =
            #"{"total_count": \#(totalCount ?? runs.count), "workflow_runs": [\#(items.joined(separator: ","))]}"#
        return HTTPResponse(statusCode: 200, body: Data(body.utf8))
    }

    private static func waiting(_ ids: [String], totalCount: Int? = nil) -> HTTPResponse {
        runs(ids.map { Run($0, "Deploy", "2026-10-08T11:59:00Z") }, totalCount: totalCount)
    }

    /// `pending_deployments` の `200`。
    private static func pending(canApprove: Bool) -> HTTPResponse {
        let body = #"[{"environment": {"name": "prod"}, "wait_timer": 0, "current_user_can_approve": \#(canApprove)}]"#
        return HTTPResponse(statusCode: 200, body: Data(body.utf8))
    }

    /// run の一覧には `list` を（`created` で絞った一覧には、`created` があればそれを）、`pending_deployments` には
    /// run の ID ごとの `pending` を返すトランスポート。
    private func transport(
        list: HTTPResponse, created: HTTPResponse? = nil,
        pending: @escaping @Sendable (String) -> HTTPResponse = { _ in HTTPResponse(statusCode: 500) }
    ) -> FakeHTTPTransport {
        FakeHTTPTransport { request in
            let components = request.url?.pathComponents ?? []
            guard components.last == "pending_deployments" else {
                let isCreated = request.url?.query()?.contains("created=") == true
                return isCreated ? created ?? list : list
            }
            return pending(components[components.count - 2])
        }
    }

    /// 通知（12:00:00）の前に作られた run の一覧。`runs` は ID と (`run_started_at`, `updated_at`) で、どれも終わった run。
    private static func created(_ runs: [(id: String, span: (startedAt: String, updatedAt: String))]) -> HTTPResponse {
        let items = runs.map { run in
            #"{"id": \#(run.id), "name": "cloudformation-apply", "status": "completed", "conclusion": "success", "#
                + #""run_started_at": "\#(run.span.startedAt)", "updated_at": "\#(run.span.updatedAt)"}"#
        }
        let body = #"{"total_count": \#(runs.count), "workflow_runs": [\#(items.joined(separator: ","))]}"#
        return HTTPResponse(statusCode: 200, body: Data(body.utf8))
    }

    private static func found(_ id: String) -> ThreadDetailsFetchResult {
        .found(ThreadDetails(state: nil, event: nil, resource: .workflowRun(id: id)))
    }

    // MARK: WorkflowRun

    @Test func takesTheOnlyWaitingRunTheUserCanApprove() async throws {
        let (thread, endpoints) = try approvalThread()
        let transport = transport(list: Self.waiting(["38692691414"])) { _ in Self.pending(canApprove: true) }
        #expect(await fetch(thread, endpoints, transport) == Self.found("38692691414"))
        #expect(
            transport.requests.map { $0.url?.absoluteString } == [
                "https://api.github.com/repos/octo/app/actions/runs?status=waiting&per_page=6",
                "https://api.github.com/repos/octo/app/actions/runs/38692691414/pending_deployments",
            ])
        #expect(transport.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer test-token-alice")
    }

    @Test func buildsTheWaitingRunsURLOnGHES() async throws {
        let (thread, endpoints) = try approvalThread(host: "ghe.example.com", repository: "team/svc")
        let transport = transport(list: Self.waiting(["1"])) { _ in Self.pending(canApprove: true) }
        _ = await fetch(thread, endpoints, transport)
        #expect(
            transport.requests.first?.url?.absoluteString
                == "https://ghe.example.com/api/v3/repos/team/svc/actions/runs?status=waiting&per_page=6")
    }

    @Test func takesTheOnlyRunTheUserCanApprove() async throws {
        let (thread, endpoints) = try approvalThread()
        let transport = transport(list: Self.waiting(["101", "102"])) { id in Self.pending(canApprove: id == "102") }
        #expect(await fetch(thread, endpoints, transport) == Self.found("102"))
        #expect(
            transport.requests.map { $0.url?.absoluteString }.dropFirst() == [
                "https://api.github.com/repos/octo/app/actions/runs/101/pending_deployments",
                "https://api.github.com/repos/octo/app/actions/runs/102/pending_deployments",
            ])
    }

    /// 承認できる run が複数あるときは、承認待ちになった時刻が通知（12:00）に最も近いものにする。10 分より離れた run は選ばない
    /// （通知の run が承認された後に待ち始めた別の run を開かないため）。
    @Test func takesTheApprovableRunClosestToTheNotification() async throws {
        let (thread, endpoints) = try approvalThread()
        let list = Self.runs([
            Run("101", "Deploy", "2026-10-08T11:50:30Z"), Run("102", "Deploy", "2026-10-08T12:01:00Z"),
        ])
        let both = transport(list: list) { _ in Self.pending(canApprove: true) }
        #expect(await fetch(thread, endpoints, both) == Self.found("102"))
        let later = Self.runs([Run("103", "Deploy", "2026-10-08T12:20:00Z")])
        #expect(
            await fetch(thread, endpoints, transport(list: later) { _ in Self.pending(canApprove: true) })
                == .unavailable)
    }

    @Test func countsARunItCannotSeeAsNotApprovable() async throws {
        let (thread, endpoints) = try approvalThread()
        let transport = transport(list: Self.waiting(["101", "102"])) { id in
            id == "101" ? HTTPResponse(statusCode: 404) : Self.pending(canApprove: true)
        }
        #expect(await fetch(thread, endpoints, transport) == Self.found("102"))
    }

    @Test(arguments: [
        ([String](), Int?.none, [Bool]()),
        (["103"], nil, [false]),
        (["101", "102"], nil, [true, true]),
        (["101", "102"], nil, [false, false]),
        (["101", "102", "103", "104", "105", "106"], nil, []),
        (["101"], 8, []),
    ])
    func findsNoWaitingRun(_ ids: [String], _ totalCount: Int?, _ approvable: [Bool]) async throws {
        let (thread, endpoints) = try approvalThread()
        let transport = transport(list: Self.waiting(ids, totalCount: totalCount)) { id in
            Self.pending(canApprove: approvable[ids.firstIndex(of: id) ?? 0])
        }
        #expect(await fetch(thread, endpoints, transport) == .unavailable)
        // 承認を待っている run から決まらないので、通知の前に作られた run の一覧も取る
        #expect(transport.requests.count == 2 + approvable.count)
        #expect(transport.requests.last?.url?.query()?.contains("created=") == true)
    }

    /// 承認を待っている run が無ければ、通知の時刻に動いていた run を探す（承認された後の通知）。
    @Test func takesTheRunSpanningAnApprovedNotification() async throws {
        let (thread, endpoints) = try approvalThread()
        let created = Self.created([
            ("14190806", ("2026-10-08T11:59:55Z", "2026-10-08T12:05:16Z")),
            ("14190661", ("2026-10-08T11:58:51Z", "2026-10-08T11:59:29Z")),
        ])
        let transport = transport(list: Self.waiting([]), created: created)
        #expect(await fetch(thread, endpoints, transport) == Self.found("14190806"))
        #expect(
            transport.requests.map { $0.url?.absoluteString } == [
                "https://api.github.com/repos/octo/app/actions/runs?status=waiting&per_page=6",
                "https://api.github.com/repos/octo/app/actions/runs?created=%3C%3D2026-10-08T12:00:00Z&per_page=30",
            ])
    }

    @Test func findsNoRunWhenTwoRunsSpanTheNotification() async throws {
        let (thread, endpoints) = try approvalThread()
        let created = Self.created([
            ("1", ("2026-10-08T11:50:00Z", "2026-10-08T12:10:00Z")),
            ("2", ("2026-10-08T11:55:00Z", "2026-10-08T12:01:00Z")),
        ])
        #expect(await fetch(thread, endpoints, transport(list: Self.waiting([]), created: created)) == .unavailable)
    }

    /// 承認を待っている run の一覧が「無い」（Actions を読めないなど）でも探す。
    @Test func searchesTheSpanningRunAfterANotFoundWaitingList() async throws {
        let (thread, endpoints) = try approvalThread()
        let created = Self.created([("14190806", ("2026-10-08T11:59:55Z", "2026-10-08T12:05:16Z"))])
        let transport = transport(list: HTTPResponse(statusCode: 404), created: created)
        #expect(await fetch(thread, endpoints, transport) == Self.found("14190806"))
    }

    /// 承認を待っている run から決まったとき、一覧が一時的な失敗・認証の失敗・レート制限のときは探さない。
    @Test func doesNotSearchTheSpanningRunAfterAWaitingRunOrAFailure() async throws {
        let (thread, endpoints) = try approvalThread()
        let created = Self.created([("2", ("2026-10-08T11:59:55Z", "2026-10-08T12:05:16Z"))])
        let decided = transport(list: Self.waiting(["1"]), created: created) { _ in Self.pending(canApprove: true) }
        #expect(await fetch(thread, endpoints, decided) == Self.found("1"))
        #expect(decided.requests.count == 2)
        for (response, result) in [
            (HTTPResponse(statusCode: 502), ThreadDetailsFetchResult.failed(.unexpectedStatus(502))),
            (HTTPResponse(statusCode: 401), .unauthorized),
            (FakeHTTPTransport.secondaryRateLimit(), .rateLimited(retryAt: now)),
        ] {
            let failing = transport(list: response, created: created)
            #expect(await fetch(thread, endpoints, failing) == result)
            #expect(failing.requests.count == 1)
        }
    }

    /// 1〜20 桁の数字でない ID は受け付けない（`Int64` に入らない 21 桁は、形の崩れたボディになる）
    @Test func rejectsInvalidRunIDs() async throws {
        let (thread, endpoints) = try approvalThread()
        #expect(await fetch(thread, endpoints, transport(list: Self.waiting(["-5"]))) == .unavailable)
        #expect(
            await fetch(thread, endpoints, transport(list: Self.waiting(["123456789012345678901"])))
                == .failed(.malformedBody))
    }

    @Test func stopsAtAFailedPendingDeploymentsRequest() async throws {
        let (thread, endpoints) = try approvalThread()
        let failing = transport(list: Self.waiting(["101", "102"])) { _ in HTTPResponse(statusCode: 502) }
        #expect(await fetch(thread, endpoints, failing) == .failed(.unexpectedStatus(502)))
        #expect(failing.requests.count == 2)
        let limited = transport(list: Self.waiting(["101", "102"])) { _ in FakeHTTPTransport.secondaryRateLimit() }
        #expect(await fetch(thread, endpoints, limited) == .rateLimited(retryAt: now))
    }

    @Test(arguments: [404, 403, 422])
    func findsNoRunWhenTheRunsCannotBeRead(_ status: Int) async throws {
        let (thread, endpoints) = try approvalThread()
        #expect(await fetch(thread, endpoints, transport(list: HTTPResponse(statusCode: status))) == .unavailable)
    }

    @Test func failsOnUnauthorizedMalformedAndRedirectedLists() async throws {
        let (thread, endpoints) = try approvalThread()
        #expect(await fetch(thread, endpoints, transport(list: HTTPResponse(statusCode: 401))) == .unauthorized)
        let malformed = HTTPResponse(statusCode: 200, body: Data(#"{"total_count": 1}"#.utf8))
        #expect(await fetch(thread, endpoints, transport(list: malformed)) == .failed(.malformedBody))
        let redirect = HTTPResponse(statusCode: 302, headers: ["Location": "https://evil.example.com/"])
        #expect(await fetch(thread, endpoints, transport(list: redirect)) == .failed(.redirect))
    }

    // MARK: CheckSuite

    @Test func takesTheClosestRunOfTheWorkflow() async throws {
        let (thread, endpoints) = try checkSuiteThread()
        let list = Self.runs([
            Run("200", "CI", "2026-10-08T11:30:00Z"), Run("201", "CI", "2026-10-08T11:59:00Z"),
            Run("202", "Release", "2026-10-08T12:00:00Z"),
        ])
        let transport = transport(list: list)
        #expect(await fetch(thread, endpoints, transport) == Self.found("201"))
        #expect(
            transport.requests.map { $0.url?.absoluteString } == [
                "https://api.github.com/repos/octo/app/actions/runs?branch=main&per_page=30"
            ])
    }

    @Test(arguments: [
        ("feat/a+b", "branch=feat/a%2Bb"),
        ("x&per_page=1", "branch=x%26per_page%3D1"),
    ])
    func escapesTheBranch(_ branch: String, _ query: String) async throws {
        let (thread, endpoints) = try checkSuiteThread(
            title: "Build and test workflow run, Attempt #2 failed for \(branch) branch")
        let transport = transport(list: Self.runs([]))
        _ = await fetch(thread, endpoints, transport)
        #expect(
            transport.requests.first?.url?.absoluteString
                == "https://api.github.com/repos/octo/app/actions/runs?\(query)&per_page=30")
    }

    @Test func findsNoRunOfTheWorkflowAndDoesNotKeepTheHTMLURL() async throws {
        let (thread, endpoints) = try checkSuiteThread()
        let list = Self.runs([Run("200", "CI", "2026-10-08T11:30:00Z"), Run("202", "Release", "2026-10-08T12:00:00Z")])
        #expect(await fetch(thread, endpoints, transport(list: list)) == .unavailable)
        // 選んだ run の ID だけが結果に入り、`html_url` は残らない
        let found = Self.runs([Run("201", "CI", "2026-10-08T12:00:00Z")])
        let result = await fetch(thread, endpoints, transport(list: found))
        #expect(result == Self.found("201"))
        #expect(!String(describing: result).contains("evil.example.com"))
    }

    /// 件名の結果と違う結果の run は、時刻が近くても選ばない。
    @Test func takesTheRunWithTheResultOfTheTitle() async throws {
        let (thread, endpoints) = try checkSuiteThread()
        let list = Self.runs([
            Run("301", "CI", "2026-10-08T12:00:00Z", "success"), Run("302", "CI", "2026-10-08T11:58:00Z", "failure"),
        ])
        #expect(await fetch(thread, endpoints, transport(list: list)) == Self.found("302"))
        let (startup, _) = try checkSuiteThread(title: "CI workflow run failed at startup for main branch")
        let startupList = Self.runs([
            Run("303", "CI", "2026-10-08T12:00:00Z", "failure"),
            Run("304", "CI", "2026-10-08T11:59:00Z", "startup_failure"),
        ])
        #expect(await fetch(startup, endpoints, transport(list: startupList)) == Self.found("304"))
    }

    @Test func findsNoRunWhenTheBranchRunsCannotBeRead() async throws {
        let (thread, endpoints) = try checkSuiteThread()
        #expect(await fetch(thread, endpoints, transport(list: HTTPResponse(statusCode: 404))) == .unavailable)
    }
}

/// run の一覧から、種類が CheckSuite のスレッドの run を選ぶ。
struct WorkflowRunSelectionTests {
    private let updatedAt = Date(timeIntervalSince1970: 1_791_460_800)  // 2026-10-08T12:00:00Z

    private func run(_ id: Int64, _ updatedAt: String) -> WorkflowRunSummary {
        WorkflowRunSummary(
            id: id, name: "CI", conclusion: "failure", status: "completed", runStartedAt: nil, updatedAt: updatedAt)
    }

    @Test func takesTheClosestRun() {
        let runs = [run(1, "2026-10-08T11:55:00Z"), run(2, "2026-10-08T12:02:00Z")]
        #expect(WorkflowRunSummary.closestRun(updatedNear: updatedAt, in: runs) == "2")
    }

    @Test func skipsRunsOutsideTheWindowOrWithoutADate() {
        let runs = [
            run(1, "2026-10-08T11:49:59Z"), run(2, "2026-10-08T12:10:01Z"), run(5, "not a date"),
            run(-1, "2026-10-08T12:00:00Z"),
        ]
        #expect(WorkflowRunSummary.closestRun(updatedNear: updatedAt, in: runs) == nil)
        #expect(WorkflowRunSummary.closestRun(updatedNear: updatedAt, in: [run(6, "2026-10-08T12:10:00Z")]) == "6")
    }

    @Test func decidesNothingOnATie() {
        let runs = [run(1, "2026-10-08T11:58:00Z"), run(2, "2026-10-08T12:02:00Z")]
        #expect(WorkflowRunSummary.closestRun(updatedNear: updatedAt, in: runs) == nil)
    }

    /// `runStartedAt`〜`updatedAt` の run。`status` が nil なら終わっていない run。
    private func span(_ id: Int64, _ startedAt: String?, _ updatedAt: String, status: String? = "completed")
        -> WorkflowRunSummary
    {
        WorkflowRunSummary(
            id: id, name: "cloudformation-apply", conclusion: nil, status: status, runStartedAt: startedAt,
            updatedAt: updatedAt)
    }

    private let now = Date(timeIntervalSince1970: 1_791_464_400)  // 2026-10-08T13:00:00Z

    /// 通知（12:00）の時刻に動いていた run が 1 件だけならその run。前に終わった run と後に始まった run は数えない。
    @Test func takesTheOnlyRunSpanningTheNotification() {
        let runs = [
            span(1, "2026-10-08T11:58:53Z", "2026-10-08T11:59:27Z"),
            span(2, "2026-10-08T11:59:55Z", "2026-10-08T12:05:14Z"),
            span(3, "2026-10-08T12:00:30Z", "2026-10-08T12:01:00Z"),
        ]
        #expect(WorkflowRunSummary.runSpanning(updatedAt, in: runs, now: now) == "2")
    }

    /// 終わっていない run は今まで動いているものとする。
    @Test func countsARunningRunAsSpanningUntilNow() {
        let running = span(4, "2026-10-08T11:59:55Z", "2026-10-08T11:59:56Z", status: "in_progress")
        #expect(WorkflowRunSummary.runSpanning(updatedAt, in: [running], now: now) == "4")
        let finished = span(5, "2026-10-08T11:59:55Z", "2026-10-08T11:59:56Z")
        #expect(WorkflowRunSummary.runSpanning(updatedAt, in: [finished], now: now) == nil)
    }

    @Test func decidesNothingForTwoOrNoSpanningRuns() {
        let two = [
            span(1, "2026-10-08T11:50:00Z", "2026-10-08T12:10:00Z"),
            span(2, "2026-10-08T11:55:00Z", "2026-10-08T11:56:00Z", status: nil),
        ]
        #expect(WorkflowRunSummary.runSpanning(updatedAt, in: two, now: now) == nil)
        #expect(WorkflowRunSummary.runSpanning(updatedAt, in: [], now: now) == nil)
        let unreadable = [span(3, nil, "2026-10-08T12:10:00Z"), span(4, "yesterday", "2026-10-08T12:10:00Z")]
        #expect(WorkflowRunSummary.runSpanning(updatedAt, in: unreadable, now: now) == nil)
    }

    /// 始まった時刻・終わった時刻と通知の時刻が同じ run は挟む run に入る。
    @Test func includesTheBoundaries() {
        #expect(
            WorkflowRunSummary.runSpanning(
                updatedAt, in: [span(1, "2026-10-08T12:00:00Z", "2026-10-08T12:05:00Z")], now: now) == "1")
        #expect(
            WorkflowRunSummary.runSpanning(
                updatedAt, in: [span(2, "2026-10-08T11:55:00Z", "2026-10-08T12:00:00Z")], now: now) == "2")
    }
}
