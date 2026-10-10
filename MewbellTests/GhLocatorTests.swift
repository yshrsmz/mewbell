import Foundation
import Testing

@testable import Mewbell

struct ExecutableValidatorTests {
    private let directory: TemporaryDirectory

    /// `/var` → `/private/var` のように、`realpath` で解決したパス
    private func realPath(_ path: String) -> String? {
        guard let pointer = realpath(path, nil) else { return nil }
        defer { free(pointer) }
        return String(cString: pointer)
    }

    init() throws {
        directory = try TemporaryDirectory()
    }

    @Test func acceptsAnExecutableRegularFile() throws {
        let path = try directory.makeFile("gh")
        #expect(ExecutableValidator.validate(path)?.path == realPath(path))
    }

    @Test(arguments: [Int16(0o777), 0o775, 0o757, 0o644])
    func rejectsWritableByOthersOrNotExecutable(_ permissions: Int16) throws {
        let path = try directory.makeFile("gh", permissions: permissions)
        #expect(ExecutableValidator.validate(path) == nil)
    }

    @Test func rejectsAFileInADirectoryOthersCanWrite() throws {
        let path = try directory.makeFile("shared/gh")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o777], ofItemAtPath: directory.url.appending(path: "shared").path)
        #expect(ExecutableValidator.validate(path) == nil)
    }

    @Test func acceptsAFileInAGroupWritableDirectory() throws {
        // Homebrew の bin は admin グループの 775
        let path = try directory.makeFile("brew/gh")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o775], ofItemAtPath: directory.url.appending(path: "brew").path)
        #expect(ExecutableValidator.validate(path) != nil)
    }

    @Test func acceptsARootOwnedExecutable() {
        #expect(ExecutableValidator.validate("/bin/sh") != nil)
    }

    @Test func rejectsADirectory() throws {
        let path = directory.url.appending(path: "gh").path
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        #expect(ExecutableValidator.validate(path) == nil)
    }

    @Test(arguments: ["gh", "bin/gh", "", "/nonexistent/gh"])
    func rejectsRelativeOrMissingPaths(_ path: String) {
        #expect(ExecutableValidator.validate(path) == nil)
    }

    @Test func resolvesSymbolicLinksToTheRealFile() throws {
        let real = try directory.makeFile("Cellar/gh/2.102.0/bin/gh")
        let link = directory.url.appending(path: "bin/gh").path
        try FileManager.default.createDirectory(
            atPath: directory.url.appending(path: "bin").path, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: real)
        let resolved = try #require(ExecutableValidator.validate(link))
        #expect(resolved.path == realPath(real))
        #expect(resolved.path != link)
    }
}

struct LoginShellTests {
    private let shells = "# List of acceptable shells\n/bin/bash\n/bin/zsh\n/opt/homebrew/bin/fish\n"

    @Test func acceptsAShellListedInEtcShells() {
        #expect(LoginShell.resolve(userShell: "/bin/zsh", allowedShells: shells) == "/bin/zsh")
    }

    @Test(arguments: ["/usr/local/bin/evil", "zsh", "", "# List of acceptable shells"])
    func rejectsUnlistedShells(_ shell: String) {
        #expect(LoginShell.resolve(userShell: shell, allowedShells: shells) == nil)
    }

    @Test func takesTheLastNonEmptyLine() {
        let output = Data("Welcome!\nnvm is loaded\n/Users/me/.local/bin/gh\n\n".utf8)
        #expect(LoginShell.lastNonEmptyLine(of: output) == "/Users/me/.local/bin/gh")
    }
}

struct GhLocatorTests {
    private let directory: TemporaryDirectory

    init() throws {
        directory = try TemporaryDirectory()
    }

    private func locator(candidates: [String], runner: FakeProcessRunner, shell: String? = "/bin/zsh") -> GhLocator {
        GhLocator(candidates: candidates, runner: runner, environment: ["HOME": "/tmp"], loginShell: { shell })
    }

    @Test func usesTheFirstValidCandidateWithoutStartingAShell() async throws {
        let first = try directory.makeFile("homebrew/gh")
        let second = try directory.makeFile("local/gh")
        let runner = FakeProcessRunner { _ in
            Issue.record("shell must not run")
            return FakeProcessRunner.output("")
        }
        let found = await locator(candidates: [first, second], runner: runner).locate()
        #expect(found?.url == ExecutableValidator.validate(first))
        #expect(found?.source == .standardLocation)
        #expect(runner.requests.isEmpty)
    }

    @Test func skipsAnInvalidCandidate() async throws {
        let writable = try directory.makeFile("homebrew/gh", permissions: 0o777)
        let valid = try directory.makeFile("local/gh")
        let runner = FakeProcessRunner { _ in FakeProcessRunner.output("") }
        let found = await locator(candidates: [writable, valid], runner: runner).locate()
        #expect(found?.url == ExecutableValidator.validate(valid))
    }

    @Test func fallsBackToTheLoginShellAndUsesTheLastLine() async throws {
        let ghFile = try directory.makeFile("custom/gh")
        let runner = FakeProcessRunner { _ in FakeProcessRunner.output("rc says hi\n\(ghFile)\n") }
        let found = await locator(candidates: ["/nonexistent/gh"], runner: runner).locate()
        #expect(found?.url == ExecutableValidator.validate(ghFile))
        #expect(found?.source == .loginShell)
        let request = try #require(runner.requests.first)
        #expect(request.executable.path == "/bin/zsh")
        #expect(request.arguments == ["-i", "-l", "-c", "command -v gh"])
        #expect(request.allowsLingeringPipes)
        #expect(request.environment == ["HOME": "/tmp"])
    }

    @Test func searchesTheLoginShellOnlyOnce() async throws {
        let runner = FakeProcessRunner { _ in FakeProcessRunner.output("", exitCode: 1) }
        let locator = locator(candidates: ["/nonexistent/gh"], runner: runner)
        #expect(await locator.locate() == nil)
        #expect(await locator.locate() == nil)
        #expect(runner.requests.count == 1)
    }

    @Test func concurrentCallersShareTheLoginShellResult() async throws {
        let ghFile = try directory.makeFile("custom/gh")
        let runner = FakeProcessRunner { _ in FakeProcessRunner.output("\(ghFile)\n") }
        let locator = locator(candidates: [], runner: runner)
        async let first = locator.locate()
        async let second = locator.locate()
        let results = await [first, second]
        #expect(results.allSatisfy { $0 != nil })
        #expect(runner.requests.count == 1)
    }

    @Test func searchesAgainOnlyWhenTheUserAsksAndNothingWasFound() async throws {
        let answer = LockedValue("")
        let runner = FakeProcessRunner { _ in FakeProcessRunner.output(answer.value) }
        let locator = locator(candidates: [], runner: runner)
        #expect(await locator.locate() == nil)
        #expect(await locator.locate() == nil)
        #expect(runner.requests.count == 1)

        // gh を入れた後、ユーザーが再読み込みを押す
        answer.value = try directory.makeFile("custom/gh") + "\n"
        #expect(await locator.locate(retryLoginShell: true) != nil)
        #expect(runner.requests.count == 2)

        // 見つかった後は、再読み込みでも探し直さない
        #expect(await locator.locate(retryLoginShell: true) != nil)
        #expect(runner.requests.count == 2)
    }

    @Test func reusesTheLoginShellResultWithoutSearchingAgain() async throws {
        let ghFile = try directory.makeFile("custom/gh")
        let runner = FakeProcessRunner { _ in FakeProcessRunner.output("\(ghFile)\n") }
        let locator = locator(candidates: [], runner: runner)
        #expect(await locator.locate() != nil)
        #expect(await locator.locate() != nil)
        #expect(runner.requests.count == 1)
    }

    @Test func rejectsARelativeAnswerFromTheShell() async throws {
        let runner = FakeProcessRunner { _ in FakeProcessRunner.output("gh\n") }
        #expect(await locator(candidates: [], runner: runner).locate() == nil)
    }

    @Test func doesNotStartAShellThatIsNotAllowed() async throws {
        let runner = FakeProcessRunner { _ in FakeProcessRunner.output("/bin/ls\n") }
        #expect(await locator(candidates: [], runner: runner, shell: nil).locate() == nil)
        #expect(runner.requests.isEmpty)
    }

    @Test func checksOnlyTheOverridePathWhenGiven() async throws {
        let candidate = try directory.makeFile("homebrew/gh")
        let override = try directory.makeFile("override/gh", permissions: 0o777)
        let runner = FakeProcessRunner { _ in FakeProcessRunner.output("") }
        let locator = locator(candidates: [candidate], runner: runner)
        #expect(await locator.locate(overridePath: override) == nil)
        #expect(runner.requests.isEmpty)
    }

    @Test func reportsAnOverridePathAsTheOverride() async throws {
        let candidate = try directory.makeFile("homebrew/gh")
        let override = try directory.makeFile("override/gh")
        let runner = FakeProcessRunner { _ in FakeProcessRunner.output("") }
        let found = await locator(candidates: [candidate], runner: runner).locate(overridePath: override)
        #expect(found == GhLocation(url: try #require(ExecutableValidator.validate(override)), source: .override))
    }
}

struct GhVersionTests {
    @Test(arguments: [
        ("gh version 2.39.2 (2023-11-14)\nhttps://github.com/cli/cli/releases/tag/v2.39.2\n", false),
        ("gh version 2.40.0 (2023-12-07)\n", true),
        ("gh version 2.102.0 (2026-09-30)\n", true),
        ("gh version 3.0.0\n", true),
    ])
    func comparesWithTheMinimum(_ output: String, _ supported: Bool) throws {
        let version = try #require(GhVersion(versionOutput: output))
        #expect(version.isSupported == supported)
    }

    @Test(arguments: ["", "gh version dev\n", "hub version 2.40.0\n"])
    func rejectsUnreadableOutput(_ output: String) {
        #expect(GhVersion(versionOutput: output) == nil)
    }
}

struct GhClientTests {
    private let ghExecutable = URL(filePath: "/opt/homebrew/bin/gh")
    private let environment = GhEnvironment.make(from: ["GH_TOKEN": "test-token", "HOME": "/tmp"])

    @Test func runsVersionWithTheSanitizedEnvironment() async throws {
        let runner = FakeProcessRunner { _ in FakeProcessRunner.output("gh version 2.102.0 (2026-09-30)\n") }
        let client = GhClient(executable: ghExecutable, runner: runner, environment: environment)
        #expect(await client.version() == GhVersion(major: 2, minor: 102, patch: 0))
        let request = try #require(runner.requests.first)
        #expect(request.executable == ghExecutable)
        #expect(request.arguments == ["--version"])
        #expect(request.environment["GH_TOKEN"] == nil)
    }

    @Test func versionIsNilWhenGhFails() async {
        let runner = FakeProcessRunner { _ in throw ProcessRunError.timedOut }
        #expect(await GhClient(executable: ghExecutable, runner: runner, environment: environment).version() == nil)
    }

    @Test func fetchesATokenForTheGivenAccount() async throws {
        let runner = FakeProcessRunner { _ in FakeProcessRunner.output("test-token\n") }
        let client = GhClient(executable: ghExecutable, runner: runner, environment: environment)
        let token = try #require(await client.token(host: "github.com", user: "alice"))
        #expect(token.value == "test-token")
        let request = try #require(runner.requests.first)
        #expect(request.arguments == ["auth", "token", "--hostname", "github.com", "--user", "alice"])
        #expect(request.environment == environment)
        #expect(request.timeout == .seconds(10))
        #expect(request.stdoutLimit == 4 * 1024)
    }

    @Test(arguments: [
        Result<ProcessOutput, ProcessRunError>.success(FakeProcessRunner.output("", exitCode: 1, stderr: "no token")),
        .success(FakeProcessRunner.output("")),
        .success(FakeProcessRunner.output("test-token\nsecond-line\n")),
        .failure(.timedOut),
        .failure(.outputTooLarge),
        .failure(.launchFailed),
    ])
    func tokenIsNilWhenGhDoesNotGiveOne(_ result: Result<ProcessOutput, ProcessRunError>) async {
        let runner = FakeProcessRunner { _ in try result.get() }
        #expect(
            await GhClient(executable: ghExecutable, runner: runner, environment: environment).token(
                host: "github.com", user: "alice") == nil)
    }
}
