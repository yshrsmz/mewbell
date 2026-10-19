import Foundation
import Testing

@testable import Mewbell

struct SubprocessRunnerTests {
    private let runner = SubprocessRunner()

    private func request(
        _ path: String, _ arguments: [String] = [], environment: [String: String] = [:],
        timeout: Duration = .seconds(5), stdoutLimit: Int = 4096
    ) -> ProcessRequest {
        ProcessRequest(
            executable: URL(filePath: path), arguments: arguments, environment: environment, timeout: timeout,
            stdoutLimit: stdoutLimit)
    }

    @Test func returnsStdoutStderrAndExitCode() async throws {
        let output = try await runner.run(request("/bin/sh", ["-c", "echo hello; echo oops >&2; exit 3"]))
        #expect(output.exitCode == 3)
        #expect(String(bytes: output.stdout, encoding: .utf8) == "hello\n")
        #expect(String(bytes: output.stderr, encoding: .utf8) == "oops\n")
    }

    /// シェルに `$0` として渡し、子の PID を書かせるファイル。
    private func pidFile(in directory: TemporaryDirectory) -> URL {
        directory.url.appending(path: "child.pid")
    }

    /// シェルが `pidFile(in:)` に書いた PID を読む。
    private func readPID(in directory: TemporaryDirectory) -> pid_t? {
        (try? String(contentsOf: pidFile(in: directory), encoding: .utf8))
            .flatMap { pid_t($0.trimmingCharacters(in: .newlines)) }
    }

    @Test func childIsGoneAfterTheTimeout() async throws {
        let directory = try TemporaryDirectory()
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: ProcessRunError.timedOut) {
            try await runner.run(
                request(
                    "/bin/sh", ["-c", "echo $$ > \"$0\"; exec /bin/sleep 60", pidFile(in: directory).path],
                    timeout: .milliseconds(500)
                )
            )
        }
        #expect(clock.now - start < .seconds(30))
        let pid = try #require(readPID(in: directory))
        // 消えなければ waitUntil が Issue を記録する
        await waitUntil { kill(pid, 0) == -1 && errno == ESRCH }
    }

    /// シェルはすぐ終わるが、バックグラウンドの sleep が標準出力を開いたまま残る。sleep の PID を `directory` に書く。
    private func lingeringRequest(in directory: TemporaryDirectory) -> ProcessRequest {
        request(
            "/bin/sh", ["-c", "/bin/sleep 60 & echo $! > \"$0\"; echo done", pidFile(in: directory).path],
            timeout: .seconds(30))
    }

    /// `lingeringRequest` が残した sleep を終了させる。PID を読めなければ、残ったかもしれないので Issue を記録する。
    private func stopLingeringChild(in directory: TemporaryDirectory) {
        guard let pid = readPID(in: directory) else {
            Issue.record("バックグラウンドの sleep の PID を読めなかった")
            return
        }
        kill(pid, SIGTERM)
    }

    @Test func returnsWhenABackgroundChildKeepsThePipeOpenIfAllowed() async throws {
        let directory = try TemporaryDirectory()
        defer { stopLingeringChild(in: directory) }
        var lingering = lingeringRequest(in: directory)
        lingering.allowsLingeringPipes = true
        let output = try await runner.run(lingering)
        #expect(output.exitCode == 0)
        #expect(String(bytes: output.stdout, encoding: .utf8) == "done\n")
    }

    @Test func failsWhenTheOutputMayBeIncomplete() async throws {
        let directory = try TemporaryDirectory()
        defer { stopLingeringChild(in: directory) }
        await #expect(throws: ProcessRunError.outputIncomplete) {
            try await runner.run(lingeringRequest(in: directory))
        }
    }

    @Test func failsWhenStdoutExceedsTheLimit() async throws {
        await #expect(throws: ProcessRunError.outputTooLarge) {
            try await runner.run(request("/usr/bin/yes", stdoutLimit: 1024))
        }
    }

    @Test func failsToLaunchAMissingExecutable() async throws {
        await #expect(throws: ProcessRunError.launchFailed) {
            try await runner.run(request("/nonexistent/gh"))
        }
    }

    @Test func passesOnlyTheGivenEnvironment() async throws {
        // 親（テストのプロセス）の環境変数は 1 つも渡らない
        let output = try await runner.run(
            request("/usr/bin/env", environment: ["MEWBELL_A": "1", "MEWBELL_B": "2"]))
        let lines = (String(bytes: output.stdout, encoding: .utf8) ?? "").split(separator: "\n").sorted()
        #expect(lines == ["MEWBELL_A=1", "MEWBELL_B=2"])
    }
}

struct GhEnvironmentTests {
    @Test func removesCredentialVariablesAndAddsNonInteractiveFlags() {
        let base = [
            "GH_TOKEN": "test-token",
            "GITHUB_TOKEN": "test-token",
            "GH_ENTERPRISE_TOKEN": "test-token",
            "GITHUB_ENTERPRISE_TOKEN": "test-token",
            "GH_HOST": "example.com",
            "HOME": "/Users/me",
            "GH_CONFIG_DIR": "/Users/me/gh",
            "GH_PROMPT_DISABLED": "0",
        ]
        let environment = GhEnvironment.make(from: base)
        #expect(
            environment == [
                "HOME": "/Users/me",
                "GH_CONFIG_DIR": "/Users/me/gh",
                "GH_PROMPT_DISABLED": "1",
                "GH_NO_UPDATE_NOTIFIER": "1",
                "NO_COLOR": "1",
            ])
    }

    @Test func setsTheOverriddenConfigDirectory() {
        let environment = GhEnvironment.make(
            from: ["GH_CONFIG_DIR": "/a"],
            configDirectory: URL(filePath: "/Users/me/.gh-work", directoryHint: .isDirectory))
        #expect(environment["GH_CONFIG_DIR"] == "/Users/me/.gh-work")
    }
}

struct AccessTokenTests {
    private func token(_ text: String) -> AccessToken? {
        AccessToken(ghOutput: Data(text.utf8))
    }

    @Test(arguments: ["", "\n", "test token", "test-token\nsecond", "tést"])
    func rejectsMalformedOutput(_ text: String) {
        #expect(token(text) == nil)
    }

    @Test func neverRevealsTheValueWhenConvertedToText() throws {
        let accessToken = try #require(token("test-token"))
        var dumped = ""
        dump(accessToken, to: &dumped)
        for text in [
            "\(accessToken)", String(reflecting: accessToken), dumped,
            "\(Mirror(reflecting: accessToken).children.map { $0.value })",
        ] {
            #expect(!text.contains("test-token"))
        }
    }
}

struct RedactionTests {
    // secret scanning に引っかからないよう、トークン風の文字列は分けて書く
    private static let tokens: [String] = [
        "gh" + "p_" + "abcDEF0123456789abcDEF0123456789abcd",
        "gh" + "o_" + "abcDEF0123456789",
        "gh" + "r_" + "abcDEF0123456789",
        "github" + "_pat_" + "11ABCDEFG0123456789_abcdef",
        // 古い形式の 40 桁 16 進のトークン
        String(repeating: "0123456789", count: 4),
    ]

    @Test(arguments: tokens)
    func redactsTokenLikeStrings(_ token: String) {
        #expect(Redaction.redactTokens(in: "error: \(token).") == "error: <redacted>.")
    }

    @Test func redactsEveryTokenInTheText() {
        let text = "a=\(Self.tokens[0]) b=\(Self.tokens[3])"
        #expect(Redaction.redactTokens(in: text) == "a=<redacted> b=<redacted>")
    }

    @Test func leavesOtherTextAlone() {
        let text = "HTTP 401: Bad credentials (https://api.github.com/user)"
        #expect(Redaction.redactTokens(in: text) == text)
    }
}
