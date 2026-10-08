import Foundation

/// 子プロセスの起動内容。シェルは経由せず、実行ファイルの絶対パスと引数の配列で起動する。
struct ProcessRequest: Sendable, Equatable {
    var executable: URL
    var arguments: [String]
    var environment: [String: String]
    var timeout: Duration
    /// 標準出力の上限（バイト）。超えたら子プロセスを終了させて `ProcessRunError.outputTooLarge` にする
    var stdoutLimit: Int
    /// 標準エラー出力の上限（バイト）。超えた分は捨てる（失敗にはしない）
    var stderrLimit: Int = 16 * 1024
    /// 子プロセスの終了後もパイプが閉じない（子が起動したバックグラウンドのプロセスが開いたまま持つ）とき、
    /// 少し待って読めた分で結果を返すか。false なら `ProcessRunError.outputIncomplete` にする
    /// （トークンのように、途中で切れた出力を受け取ってはいけない場合）
    var allowsLingeringPipes = false
}

struct ProcessOutput: Sendable, Equatable {
    var exitCode: Int32
    var stdout: Data
    var stderr: Data
}

enum ProcessRunError: Error, Equatable, Sendable {
    case launchFailed
    case timedOut
    case outputTooLarge
    /// 子プロセスは終わったが、出力を最後まで読めなかった
    case outputIncomplete
}

/// 子プロセスの実行。テストでは偽物に差し替える。
protocol ProcessRunning: Sendable {
    func run(_ request: ProcessRequest) async throws -> ProcessOutput
}
