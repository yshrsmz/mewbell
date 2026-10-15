import Foundation
import Testing

@testable import Mewbell

// WorkflowRun（デプロイの承認リクエスト）のスレッドの run の検索
extension ThreadDetailsPollingTests {
    static let waitingRun = ThreadDetails(state: nil, event: nil, resource: .workflowRun(id: "38692691414"))

    /// 種類が WorkflowRun のスレッドの一覧。
    static func approvals(_ ids: [Int]) -> HTTPResponse {
        let json = ids.map { id in
            FakeHTTPTransport.threadJSON(
                id: String(id), type: "WorkflowRun", title: "bob requested your review to deploy to an environment")
        }
        return PollerFixture.ok(body: Data("[\(json.joined(separator: ","))]".utf8))
    }

    /// 承認を待っている run の一覧には run `38692691414` だけを返し、その `pending_deployments` には承認できる待ちを返す。
    static func waitingRuns(_ request: URLRequest) -> HTTPResponse {
        if request.url?.lastPathComponent == "pending_deployments" {
            return HTTPResponse(statusCode: 200, body: Data(#"[{"current_user_can_approve": true}]"#.utf8))
        }
        let body =
            #"{"total_count": 1, "workflow_runs": [{"id": 38692691414, "name": "Deploy", "updated_at": "2026-10-08T12:00:00Z"}]}"#
        return HTTPResponse(statusCode: 200, body: Data(body.utf8))
    }

    @Test func findsTheRunOfNewApprovalsBeforePublishing() async throws {
        let fixture = try PollerFixture()
        respond(fixture, notifications: [Self.approvals([1]), Self.approvals([1, 2])], details: Self.waitingRuns)
        fixture.poller.start()
        await fixture.sleeper.waitForSleeps(1)
        fixture.advance(by: 60)
        await fixture.sleeper.waitForSleeps(2)
        let first = try #require(firstUpdate(containing: "2", fixture))
        #expect(first.threads.first { $0.id == "2" }?.details == Self.waitingRun)
        let urls = detailsRequests(fixture).compactMap { $0.url?.absoluteString }
        #expect(
            Set(urls) == [
                "https://api.github.com/repos/octo/app/actions/runs?status=waiting&per_page=20",
                "https://api.github.com/repos/octo/app/actions/runs/38692691414/pending_deployments",
            ])
        // 1 は最初の一覧の後に、2 は知らせる前に 1 回ずつ探し（一覧と `pending_deployments` の 2 回ずつ）、
        // 同じ `updated_at` の間は探し直さない
        #expect(urls.count == 4)
        fixture.advance(by: 300)
        await fixture.sleeper.waitForSleeps(3)
        #expect(detailsRequests(fixture).count == 4)
        fixture.poller.stop()
    }
}
