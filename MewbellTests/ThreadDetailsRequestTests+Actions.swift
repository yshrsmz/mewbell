import Foundation
import Testing

@testable import Mewbell

// WorkflowRun と CheckSuite のスレッドの `GitHubAPIClient.fetchDetails` のリクエストと結果
// （github-api の「ワークフローの実行の検索の」で始まる要件）。スレッドの `updated_at` は 2026-10-08T12:00:00Z
extension ThreadDetailsRequestTests {
    private func approvalThread() throws -> (NotificationThread, APIEndpoints) {
        try thread(
            subjectURL: nil, type: "WorkflowRun", title: "bob requested your review to deploy to an environment")
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

    /// run の一覧の `200`。`html_url` は攻撃者のホストにしておく（使わないことは型が保証する）。
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

    /// 承認できても通知（12:00）から 10 分より離れて待ち始めた run は選ばない（通知の run が承認された後に待ち始めた
    /// 別の run を開かないため）。通知の 1 分前に待ち始めた承認できない run があるので、通知の run がまだ待っているかも
    /// しれず、通知の前に作られた run の一覧は取らない。
    @Test func rejectsAnApprovableRunThatStartedWaitingLater() async throws {
        let (thread, endpoints) = try approvalThread()
        let later = transport(
            list: Self.runs([
                Run("102", "Deploy", "2026-10-08T11:59:00Z"), Run("103", "Deploy", "2026-10-08T12:20:00Z"),
            ])
        ) { id in Self.pending(canApprove: id == "103") }
        #expect(await fetch(thread, endpoints, later) == .unavailable)
        #expect(
            later.requests.map { $0.url?.absoluteString } == [
                "https://api.github.com/repos/octo/app/actions/runs?status=waiting&per_page=6",
                "https://api.github.com/repos/octo/app/actions/runs/102/pending_deployments",
                "https://api.github.com/repos/octo/app/actions/runs/103/pending_deployments",
            ])
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
        (["101", "102", "103", "104", "105", "106"], nil, []),
        (["101"], 8, []),
    ])
    func findsNoWaitingRun(_ ids: [String], _ totalCount: Int?, _ approvable: [Bool]) async throws {
        let (thread, endpoints) = try approvalThread()
        let transport = transport(list: Self.waiting(ids, totalCount: totalCount)) { id in
            Self.pending(canApprove: approvable[ids.firstIndex(of: id) ?? 0])
        }
        #expect(await fetch(thread, endpoints, transport) == .unavailable)
        // 通知の前に作られた run の一覧は、通知の前後に待ち始めた run が無いときだけ取る（このテストの承認を待っている
        // run は、どれも通知の 1 分前に待ち始めたもの。そういう run があるのに決まらないときは、通知の run がまだ
        // 待っているかもしれないので探さない）
        let searchesSpanning = ids.isEmpty
        #expect(transport.requests.count == 1 + approvable.count + (searchesSpanning ? 1 : 0))
        #expect((transport.requests.last?.url?.query()?.contains("created=") ?? false) == searchesSpanning)
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

    /// 通知の前に作られた run の一覧を取るまでに承認を待ち始めた run は、通知の時刻に動いていても数えない。
    @Test func doesNotTakeBackAWaitingRunItRejected() async throws {
        let (thread, endpoints) = try approvalThread()
        let waitingRun =
            #"{"id": 103, "name": "Deploy", "status": "waiting", "run_started_at": "2026-10-08T11:55:00Z", "#
            + #""updated_at": "2026-10-08T11:56:00Z"}"#
        let list = HTTPResponse(
            statusCode: 200, body: Data(#"{"total_count": 1, "workflow_runs": [\#(waitingRun)]}"#.utf8))
        let transport = transport(list: Self.waiting([]), created: list)
        #expect(await fetch(thread, endpoints, transport) == .unavailable)
        #expect(transport.requests.count == 2)
    }

    /// 承認を待っている run が通知から離れた時刻に待ち始めたものだけなら、通知の run はもう承認されたものとして探す。
    /// 承認を待っている run を全部は見られない（`total_count` が一覧より多い）ときは探さない。
    @Test func searchesTheSpanningRunPastUnrelatedWaitingRuns() async throws {
        let (thread, endpoints) = try approvalThread()
        let created = Self.created([("14190806", ("2026-10-08T11:59:55Z", "2026-10-08T12:05:16Z"))])
        let later = Self.runs([Run("201", "Deploy", "2026-10-08T15:00:00Z")])
        let searched = transport(list: later, created: created) { _ in Self.pending(canApprove: true) }
        #expect(await fetch(thread, endpoints, searched) == Self.found("14190806"))
        #expect(searched.requests.count == 2)
        let partial = Self.runs([Run("201", "Deploy", "2026-10-08T15:00:00Z")], totalCount: 7)
        let unseen = transport(list: partial, created: created)
        #expect(await fetch(thread, endpoints, unseen) == .unavailable)
        #expect(unseen.requests.count == 1)
    }

    /// 承認を待っている run の一覧が「無い」（Actions を読めないなど）でも探す。
    @Test func searchesTheSpanningRunAfterANotFoundWaitingList() async throws {
        let (thread, endpoints) = try approvalThread()
        let created = Self.created([("14190806", ("2026-10-08T11:59:55Z", "2026-10-08T12:05:16Z"))])
        let transport = transport(list: HTTPResponse(statusCode: 404), created: created)
        #expect(await fetch(thread, endpoints, transport) == Self.found("14190806"))
    }

    /// 承認を待っている run から決まったとき、一覧がレート制限のときは探さない。
    @Test func doesNotSearchTheSpanningRunAfterAWaitingRunOrARateLimit() async throws {
        let (thread, endpoints) = try approvalThread()
        let created = Self.created([("2", ("2026-10-08T11:59:55Z", "2026-10-08T12:05:16Z"))])
        let decided = transport(list: Self.waiting(["1"]), created: created) { _ in Self.pending(canApprove: true) }
        #expect(await fetch(thread, endpoints, decided) == Self.found("1"))
        #expect(decided.requests.count == 2)
        let failing = transport(list: FakeHTTPTransport.secondaryRateLimit(), created: created)
        #expect(await fetch(thread, endpoints, failing) == .rateLimited(retryAt: now))
        #expect(failing.requests.count == 1)
    }

    /// 1〜20 桁の数字でない ID は受け付けない
    @Test func rejectsInvalidRunIDs() async throws {
        let (thread, endpoints) = try approvalThread()
        #expect(await fetch(thread, endpoints, transport(list: Self.waiting(["-5"]))) == .unavailable)
    }

    @Test func stopsAtAFailedPendingDeploymentsRequest() async throws {
        let (thread, endpoints) = try approvalThread()
        let failing = transport(list: Self.waiting(["101", "102"])) { _ in HTTPResponse(statusCode: 502) }
        #expect(await fetch(thread, endpoints, failing) == .failed(.unexpectedStatus(502)))
        #expect(failing.requests.count == 2)
    }

    /// 共通の取得の失敗は Issue の経路で確かめる
    @Test func findsNoRunWhenTheRunsCannotBeRead() async throws {
        let (thread, endpoints) = try approvalThread()
        #expect(await fetch(thread, endpoints, transport(list: HTTPResponse(statusCode: 404))) == .unavailable)
    }

    @Test func failsOnAMalformedList() async throws {
        let (thread, endpoints) = try approvalThread()
        let malformed = HTTPResponse(statusCode: 200, body: Data(#"{"total_count": 1}"#.utf8))
        #expect(await fetch(thread, endpoints, transport(list: malformed)) == .failed(.malformedBody))
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

    @Test func findsNoRunOfTheWorkflow() async throws {
        let (thread, endpoints) = try checkSuiteThread()
        let list = Self.runs([Run("200", "CI", "2026-10-08T11:30:00Z"), Run("202", "Release", "2026-10-08T12:00:00Z")])
        #expect(await fetch(thread, endpoints, transport(list: list)) == .unavailable)
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
}
