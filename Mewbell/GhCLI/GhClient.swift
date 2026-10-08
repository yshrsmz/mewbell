import Foundation
import os

/// 検証済みの gh 実行ファイルでコマンドを実行する。
struct GhClient: Sendable {
    private static let logger = Logger(category: "GhCLI")

    let executable: URL
    let runner: any ProcessRunning
    /// `GhEnvironment.make(from:)` で作った環境
    let environment: [String: String]

    /// `gh --version` の結果。実行できない・読めないときは nil。
    func version() async -> GhVersion? {
        guard let output = await run(["--version"], timeout: .seconds(5), stdoutLimit: 4 * 1024),
            output.exitCode == 0
        else { return nil }
        return GhVersion(versionOutput: String(bytes: output.stdout, encoding: .utf8) ?? "")
    }

    /// `gh auth token --hostname <host> --user <user>` の結果。取得できないときは nil。
    /// `host` と `user` は検証済み（`GhIdentifier`）の値を渡す。
    func token(host: String, user: String) async -> AccessToken? {
        guard
            let output = await run(
                ["auth", "token", "--hostname", host, "--user", user], timeout: .seconds(10), stdoutLimit: 4 * 1024)
        else { return nil }
        guard output.exitCode == 0 else {
            let stderr = Redaction.redactTokens(in: String(bytes: output.stderr, encoding: .utf8) ?? "")
            Self.logger.error("gh auth token exited with \(output.exitCode): \(stderr)")
            return nil
        }
        guard let token = AccessToken(ghOutput: output.stdout) else {
            Self.logger.error("gh auth token printed an unexpected output")
            return nil
        }
        return token
    }

    private func run(_ arguments: [String], timeout: Duration, stdoutLimit: Int) async -> ProcessOutput? {
        let request = ProcessRequest(
            executable: executable, arguments: arguments, environment: environment, timeout: timeout,
            stdoutLimit: stdoutLimit)
        do {
            return try await runner.run(request)
        } catch {
            Self.logger.error("gh \(arguments.first ?? "") failed: \(String(describing: error))")
            return nil
        }
    }
}
