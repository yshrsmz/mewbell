import Foundation

/// ワークフローの実行（run）の一覧（`GET /repos/{owner}/{repo}/actions/runs`）のうち、run を選ぶのに使う値だけ。
/// `html_url` などの URL は型に載せない。
struct WorkflowRunsPage: Decodable, Sendable {
    let totalCount: Int
    let workflowRuns: [WorkflowRunSummary]

    /// レスポンスボディを読む。形が崩れていれば nil。
    static func decode(from data: Data) -> WorkflowRunsPage? {
        try? APIJSON.decoder().decode(WorkflowRunsPage.self, from: data)
    }
}

/// 1 つの run のうち、選ぶのに使う値だけ。
struct WorkflowRunSummary: Decodable, Sendable {
    let id: Int64
    /// ワークフロー名（実行の表示名は `display_title` で、使わない）
    let name: String?
    /// 結果（`failure`・`success` など）。終わっていなければ nil
    let conclusion: String?
    /// 状態（`completed`・`in_progress`・`waiting` など）
    let status: String?
    /// 始まった時刻（`run_started_at`）
    let runStartedAt: String?
    let updatedAt: String

    /// 検証した run の ID（1〜20 桁の数字）。通らなければ nil。
    var validatedID: String? {
        let id = String(id)
        return ThreadID.isValid(id) ? id : nil
    }

    /// run を選ぶとき、`updated_at` の差として許す幅
    private static let matchWindow: TimeInterval = 600

    /// `runs` のうち、`updated_at` と `updatedAt` の差が `matchWindow` 以内で最も小さいものの ID。当たらないとき、
    /// 差が最も小さいものが 2 件以上あるときは nil。
    static func closestRun(updatedNear updatedAt: Date, in runs: [WorkflowRunSummary]) -> String? {
        let candidates = runs.compactMap { run -> (id: String, distance: TimeInterval)? in
            guard let id = run.validatedID,
                let runUpdatedAt = try? Date(run.updatedAt, strategy: .iso8601)
            else { return nil }
            let distance = abs(runUpdatedAt.timeIntervalSince(updatedAt))
            return distance <= matchWindow ? (id, distance) : nil
        }
        guard let closest = candidates.map(\.distance).min() else { return nil }
        let closestRuns = candidates.filter { $0.distance == closest }
        return closestRuns.count == 1 ? closestRuns[0].id : nil
    }

    /// `runs` のうち、`run_started_at` が `date` 以前で、終わった時刻（`status` が `completed` なら `updated_at`、
    /// そうでなければ `now`）が `date` 以降のもの（`date` に動いていた run）が 1 件だけなら、その ID。日時を読めない run は数えない。
    static func runSpanning(_ date: Date, in runs: [WorkflowRunSummary], now: Date) -> String? {
        let spanning = runs.compactMap { run -> String? in
            guard let id = run.validatedID,
                let startedAt = run.runStartedAt.flatMap({ try? Date($0, strategy: .iso8601) }),
                let updatedAt = try? Date(run.updatedAt, strategy: .iso8601)
            else { return nil }
            let endedAt = run.status == "completed" ? updatedAt : now
            return startedAt <= date && date <= endedAt ? id : nil
        }
        return spanning.count == 1 ? spanning[0] : nil
    }
}

/// run の承認の待ち（`GET /repos/{owner}/{repo}/actions/runs/{run_id}/pending_deployments` の要素）のうち、使う値だけ。
struct PendingDeployment: Decodable, Sendable {
    let currentUserCanApprove: Bool

    /// レスポンスボディ（配列）を読む。形が崩れていれば nil。
    static func decodeList(from data: Data) -> [PendingDeployment]? {
        try? APIJSON.decoder().decode([PendingDeployment].self, from: data)
    }
}
