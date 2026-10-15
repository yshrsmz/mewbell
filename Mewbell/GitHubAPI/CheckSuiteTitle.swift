import Foundation

/// 種類が CheckSuite の通知の件名（`<ワークフロー名> workflow run[, Attempt #<数字>] <結果> for <ブランチ> branch`）から読んだ値。
/// 試行の回数は読むが持たない（run を選ぶのにも開く URL にも使わない）。
struct CheckSuiteTitle: Hashable, Sendable {
    /// ワークフローの実行の結果
    enum Result: String, Sendable {
        case failed
        case failedAtStartup = "failed at startup"
        case cancelled
        case skipped
        case succeeded

        /// run の一覧の `conclusion` の値
        var conclusion: String {
            switch self {
            case .failed: "failure"
            case .failedAtStartup: "startup_failure"
            case .cancelled: "cancelled"
            case .skipped: "skipped"
            case .succeeded: "success"
            }
        }
    }

    let workflowName: String
    let result: Result
    let branch: String

    /// 件名を読む。形が合わない、知らない結果、ワークフロー名かブランチが空・UTF-8 で 255 バイトより長い・制御文字を含むときは nil。
    init?(_ title: String) {
        let pattern =
            /^(.+?) workflow run(?:, Attempt #[0-9]+)? (failed at startup|failed|cancelled|skipped|succeeded) for (.+) branch$/
        guard let match = title.wholeMatch(of: pattern), let result = Result(rawValue: String(match.output.2)) else {
            return nil
        }
        let workflowName = String(match.output.1)
        let branch = String(match.output.3)
        guard Self.isValid(workflowName), Self.isValid(branch) else { return nil }
        self.workflowName = workflowName
        self.result = result
        self.branch = branch
    }

    private static func isValid(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 255
            && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}
