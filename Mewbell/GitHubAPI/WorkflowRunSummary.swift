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
    let updatedAt: String

    /// 検証した run の ID（1〜20 桁の数字）。通らなければ nil。
    var validatedID: String? {
        let id = String(id)
        return ThreadID.isValid(id) ? id : nil
    }

    /// run を選ぶとき、`updated_at` の差として許す幅
    static let matchWindow: TimeInterval = 600

    /// `runs` のうち、`name` が `workflowName` と一致し、`updated_at` と `updatedAt` の差が `matchWindow` 以内で最も
    /// 小さいものの ID。当たらないとき、差が最も小さいものが 2 件以上あるときは nil。
    static func closestRun(named workflowName: String, updatedNear updatedAt: Date, in runs: [WorkflowRunSummary])
        -> String?
    {
        let candidates = runs.compactMap { run -> (id: String, distance: TimeInterval)? in
            guard run.name == workflowName, let id = run.validatedID,
                let runUpdatedAt = try? Date(run.updatedAt, strategy: .iso8601)
            else { return nil }
            let distance = abs(runUpdatedAt.timeIntervalSince(updatedAt))
            return distance <= matchWindow ? (id, distance) : nil
        }
        guard let closest = candidates.map(\.distance).min() else { return nil }
        let closestRuns = candidates.filter { $0.distance == closest }
        return closestRuns.count == 1 ? closestRuns[0].id : nil
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
