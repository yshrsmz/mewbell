import Foundation
import Testing

@testable import Mewbell

/// run の一覧から、スレッドの run を選ぶ（通知の時刻に最も近い run、通知の時刻に動いていた run）。
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

    @Test func findsARunUpdatedNearTheNotification() {
        #expect(WorkflowRunSummary.hasRun(updatedNear: updatedAt, in: [run(1, "2026-10-08T12:10:00Z")]))
        #expect(!WorkflowRunSummary.hasRun(updatedNear: updatedAt, in: [run(2, "2026-10-08T12:10:01Z")]))
        #expect(!WorkflowRunSummary.hasRun(updatedNear: updatedAt, in: [run(3, "not a date")]))
        #expect(!WorkflowRunSummary.hasRun(updatedNear: updatedAt, in: []))
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

    /// 通知（12:00）の時刻に動いていた run が 1 件だけならその run。前に終わった run と後に始まった run は数えない。
    @Test func takesTheOnlyRunSpanningTheNotification() {
        let runs = [
            span(1, "2026-10-08T11:58:53Z", "2026-10-08T11:59:27Z"),
            span(2, "2026-10-08T11:59:55Z", "2026-10-08T12:05:14Z"),
            span(3, "2026-10-08T12:00:30Z", "2026-10-08T12:01:00Z"),
        ]
        #expect(WorkflowRunSummary.runSpanning(updatedAt, in: runs) == "2")
    }

    /// 終わっていない run は今も動いているものとする（`updated_at` が通知の前でも、終わりを決めない）。
    @Test func countsARunningRunAsSpanningUntilNow() {
        let running = span(4, "2026-10-08T11:59:55Z", "2026-10-08T11:59:56Z", status: "in_progress")
        #expect(WorkflowRunSummary.runSpanning(updatedAt, in: [running]) == "4")
        let finished = span(5, "2026-10-08T11:59:55Z", "2026-10-08T11:59:56Z")
        #expect(WorkflowRunSummary.runSpanning(updatedAt, in: [finished]) == nil)
    }

    @Test func decidesNothingForTwoOrNoSpanningRuns() {
        let two = [
            span(1, "2026-10-08T11:50:00Z", "2026-10-08T12:10:00Z"),
            span(2, "2026-10-08T11:55:00Z", "2026-10-08T11:56:00Z", status: nil),
        ]
        #expect(WorkflowRunSummary.runSpanning(updatedAt, in: two) == nil)
        #expect(WorkflowRunSummary.runSpanning(updatedAt, in: []) == nil)
        let unreadable = [span(3, nil, "2026-10-08T12:10:00Z"), span(4, "yesterday", "2026-10-08T12:10:00Z")]
        #expect(WorkflowRunSummary.runSpanning(updatedAt, in: unreadable) == nil)
    }

    /// 始まった時刻・終わった時刻と通知の時刻が同じ run は挟む run に入る。
    @Test func includesTheBoundaries() {
        #expect(
            WorkflowRunSummary.runSpanning(
                updatedAt, in: [span(1, "2026-10-08T12:00:00Z", "2026-10-08T12:05:00Z")]) == "1")
        #expect(
            WorkflowRunSummary.runSpanning(
                updatedAt, in: [span(2, "2026-10-08T11:55:00Z", "2026-10-08T12:00:00Z")]) == "2")
    }
}
