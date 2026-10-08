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

    @Test func returnsStdoutAndExitCode() async throws {
        let output = try await runner.run(request("/bin/echo", ["hello"]))
        #expect(output.exitCode == 0)
        #expect(String(bytes: output.stdout, encoding: .utf8) == "hello\n")
    }

    @Test func returnsNonZeroExitCodeAndStderr() async throws {
        let output = try await runner.run(request("/bin/sh", ["-c", "echo oops >&2; exit 3"]))
        #expect(output.exitCode == 3)
        #expect(String(bytes: output.stderr, encoding: .utf8) == "oops\n")
    }

    @Test func timesOutAndStopsTheChild() async throws {
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: ProcessRunError.timedOut) {
            try await runner.run(request("/bin/sleep", ["5"], timeout: .milliseconds(500)))
        }
        #expect(clock.now - start < .seconds(3))
    }

    @Test func childIsGoneAfterTheTimeout() async throws {
        let pidFile = FileManager.default.temporaryDirectory.appending(path: "MewbellTests-\(UUID().uuidString).pid")
        defer { try? FileManager.default.removeItem(at: pidFile) }
        await #expect(throws: ProcessRunError.timedOut) {
            try await runner.run(
                request(
                    "/bin/sh", ["-c", "echo $$ > \"$0\"; exec /bin/sleep 5", pidFile.path], timeout: .milliseconds(500))
            )
        }
        let pid = try #require(
            pid_t(try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .newlines)))
        try await Task.sleep(for: .milliseconds(300))
        #expect(kill(pid, 0) == -1 && errno == ESRCH)
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
        let environment = GhEnvironment.make(from: ["GH_TOKEN": "test-token", "GH_HOST": "example.com", "HOME": "/tmp"])
        let output = try await runner.run(request("/usr/bin/env", environment: environment))
        let lines = (String(bytes: output.stdout, encoding: .utf8) ?? "").split(separator: "\n")
        #expect(!lines.contains { $0.hasPrefix("GH_TOKEN=") })
        #expect(!lines.contains { $0.hasPrefix("GH_HOST=") })
        #expect(lines.contains("HOME=/tmp"))
        #expect(lines.contains("GH_PROMPT_DISABLED=1"))
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
}

struct AccessTokenTests {
    private func token(_ text: String) -> AccessToken? {
        AccessToken(ghOutput: Data(text.utf8))
    }

    @Test func acceptsASingleLineAndTrimsIt() throws {
        let accessToken = try #require(token("  test-token\n"))
        #expect(accessToken.value == "test-token")
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
    private let classic = "gh" + "p_" + "abcDEF0123456789abcDEF0123456789abcd"
    private let oauth = "gh" + "o_" + "abcDEF0123456789"
    private let fineGrained = "github" + "_pat_" + "11ABCDEFG0123456789_abcdef"

    @Test func redactsTokenLikeStrings() {
        let text = "error: \(classic) and \(oauth), also \(fineGrained)."
        let redacted = Redaction.redactTokens(in: text)
        #expect(redacted == "error: <redacted> and <redacted>, also <redacted>.")
    }

    @Test func leavesOtherTextAlone() {
        let text = "HTTP 401: Bad credentials (https://api.github.com/user)"
        #expect(Redaction.redactTokens(in: text) == text)
    }
}
