import Foundation
import Synchronization
import Testing

@testable import Mewbell

struct AccountTests {
    @Test func lowercasesTheHostInTheID() {
        #expect(AccountID(host: "GHE.Example.com", user: "Dave").description == "ghe.example.com/Dave")
    }

    @Test func sortsGitHubDotComFirstAndTheActiveUserFirst() {
        let hostsFile = HostsFile(hosts: [
            .init(name: "ghe.example.com", users: ["dave"], activeUser: "dave"),
            .init(name: "acme.ghe.com", users: ["erin"], activeUser: nil),
            .init(name: "github.com", users: ["alice", "bob", "Carol"], activeUser: "bob"),
        ])
        let ids = Account.accounts(from: hostsFile).map(\.id.description)
        #expect(
            ids == [
                "github.com/bob", "github.com/alice", "github.com/Carol", "acme.ghe.com/erin", "ghe.example.com/dave",
            ])
    }
}

/// gh を偽物にした `AccountDiscovery` のテスト環境。
final class DiscoveryFixture: Sendable {
    let directory: TemporaryDirectory
    let ghPath: String
    let credentials = CredentialStore()
    let runner: FakeProcessRunner
    private let versionOutput = LockedValue("gh version 2.102.0 (2026-09-30)\n")
    private let failingUsers = LockedValue<Set<String>>([])

    init() throws {
        let directory = try TemporaryDirectory()
        self.directory = directory
        ghPath = try directory.makeFile("bin/gh")
        let versionOutput = versionOutput
        let failingUsers = failingUsers
        runner = FakeProcessRunner { request in
            if request.arguments == ["--version"] {
                return FakeProcessRunner.output(versionOutput.value)
            }
            let user = request.arguments.last ?? ""
            if failingUsers.value.contains(user) {
                return FakeProcessRunner.output("", exitCode: 1, stderr: "no oauth token found")
            }
            return FakeProcessRunner.output("test-token-\(user)\n")
        }
    }

    var configDirectory: URL { directory.url.appending(path: "config") }

    func discovery(candidates: [String]? = nil, runner: (any ProcessRunning)? = nil) -> AccountDiscovery {
        let runner = runner ?? self.runner
        let locator = GhLocator(
            candidates: candidates ?? [ghPath], runner: runner, environment: [:], loginShell: { nil })
        return AccountDiscovery(
            locator: locator, runner: runner, environment: [:],
            configDirectory: GhConfigDirectory.Resolved(url: configDirectory, source: .defaultLocation),
            credentials: credentials)
    }

    func writeHosts(_ yaml: String) throws {
        try directory.makeFile("config/hosts.yml", contents: yaml, permissions: 0o600)
    }

    func setVersion(_ output: String) {
        versionOutput.value = output
    }

    func setFailing(_ users: Set<String>) {
        failingUsers.value = users
    }

    var tokenRequests: [[String]] {
        runner.requests.map(\.arguments).filter { $0.first == "auth" }
    }
}

struct AccountDiscoveryTests {
    private let fixture: DiscoveryFixture
    private let twoAccounts = """
        github.com:
            users:
                alice:
            user: alice
        ghe.example.com:
            users:
                dave:
            user: dave
        """

    init() throws {
        fixture = try DiscoveryFixture()
    }

    private func reload(_ discovery: AccountDiscovery) async -> [DiscoveryState] {
        let states = LockedValue<[DiscoveryState]>([])
        await discovery.reload(userInitiated: false, options: DiscoveryOptions()) { state in
            states.withLock { $0.append(state) }
        }
        return states.value
    }

    private func status(_ host: String, _ user: String, _ state: TokenState, active: Bool = true) -> AccountStatus {
        AccountStatus(account: Account(id: AccountID(host: host, user: user), isActive: active), tokenState: state)
    }

    @Test func reportsAGhThatCannotRunAndChecksAgainNextTime() async throws {
        try fixture.writeHosts(twoAccounts)
        fixture.setVersion("")
        let discovery = fixture.discovery()
        #expect(await reload(discovery).last == .ghUnavailable)
        fixture.setVersion("gh version 2.102.0 (2026-09-30)\n")
        #expect(await reload(discovery).last?.hasAccounts == true)
    }

    @Test func reportsNotLoggedInWithoutHostsFile() async {
        let states = await reload(fixture.discovery())
        #expect(states.last == .notLoggedIn)
    }

    @Test func reportsAnUnreadableHostsFileEvenWhenGhCannotStart() async throws {
        // gh は hosts.yml を解釈できないと --version でも失敗する
        fixture.setVersion("")
        try fixture.writeHosts("github.com: [unclosed")
        let states = await reload(fixture.discovery())
        #expect(states.last == .hostsFileUnreadable(path: fixture.configDirectory.appending(path: "hosts.yml").path))
    }

    @Test func fetchesTokensForEveryAccount() async throws {
        try fixture.writeHosts(twoAccounts)
        fixture.setFailing(["dave"])
        let states = await reload(fixture.discovery())
        #expect(
            states == [
                .accounts([status("github.com", "alice", .fetching), status("ghe.example.com", "dave", .fetching)]),
                .accounts([status("github.com", "alice", .ready), status("ghe.example.com", "dave", .unavailable)]),
            ])
        let alice = try #require(await fixture.credentials.token(for: AccountID(host: "github.com", user: "alice")))
        #expect(alice.value == "test-token-alice")
        #expect(fixture.tokenRequests.contains(["auth", "token", "--hostname", "github.com", "--user", "alice"]))
    }

    @Test func doesNotRunGhAgainForReadyAccountsButRetriesFailedOnes() async throws {
        try fixture.writeHosts(twoAccounts)
        fixture.setFailing(["dave"])
        let discovery = fixture.discovery()
        _ = await reload(discovery)
        fixture.setFailing([])
        let states = await reload(discovery)
        #expect(
            states.last
                == .accounts([status("github.com", "alice", .ready), status("ghe.example.com", "dave", .ready)]))
        let aliceRequests = fixture.tokenRequests.filter { $0.last == "alice" }
        let daveRequests = fixture.tokenRequests.filter { $0.last == "dave" }
        #expect(aliceRequests.count == 1)
        #expect(daveRequests.count == 2)
        #expect(fixture.runner.requests.filter { $0.arguments == ["--version"] }.count == 1)
    }

    @Test func discardsTheTokenOfARemovedAccount() async throws {
        try fixture.writeHosts(twoAccounts)
        let discovery = fixture.discovery()
        _ = await reload(discovery)
        try fixture.writeHosts("github.com:\n    users:\n        alice:\n    user: alice\n")
        let states = await reload(discovery)
        #expect(states.last == .accounts([status("github.com", "alice", .ready)]))
        #expect(await fixture.credentials.token(for: AccountID(host: "github.com", user: "alice")) != nil)
        #expect(await fixture.credentials.token(for: AccountID(host: "ghe.example.com", user: "dave")) == nil)
    }

    @Test func discardsEveryTokenWhenNoLongerLoggedIn() async throws {
        try fixture.writeHosts(twoAccounts)
        let discovery = fixture.discovery()
        _ = await reload(discovery)
        try FileManager.default.removeItem(at: fixture.configDirectory.appending(path: "hosts.yml"))
        let states = await reload(discovery)
        #expect(states.last == .notLoggedIn)
        #expect(await fixture.credentials.token(for: AccountID(host: "github.com", user: "alice")) == nil)
    }

    private let alice = AccountID(host: "github.com", user: "alice")

    @Test func refreshesATokenFromGh() async throws {
        try fixture.writeHosts(twoAccounts)
        let discovery = fixture.discovery()
        _ = await reload(discovery)
        await fixture.credentials.set(try #require(AccessToken(ghOutput: Data("old-token".utf8))), for: alice)
        let token = await discovery.refreshToken(for: alice)
        #expect(token?.value == "test-token-alice")
        #expect(await fixture.credentials.token(for: alice)?.value == "test-token-alice")
        #expect(fixture.tokenRequests.filter { $0.last == "alice" }.count == 2)
    }

    @Test func dropsTheOldTokenWhenRefreshingFails() async throws {
        try fixture.writeHosts(twoAccounts)
        let discovery = fixture.discovery()
        _ = await reload(discovery)
        fixture.setFailing(["alice"])
        #expect(await discovery.refreshToken(for: alice) == nil)
        #expect(await fixture.credentials.token(for: alice) == nil)
    }

    @Test func doesNotStoreATokenForAnAccountRemovedWhileRefreshing() async throws {
        try fixture.writeHosts(twoAccounts)
        let gated = GatedProcessRunner(base: fixture.runner)
        let discovery = fixture.discovery(runner: gated)
        _ = await reload(discovery)
        gated.close()
        async let refreshed = discovery.refreshToken(for: alice)
        await gated.waitUntilWaiting(1)
        try fixture.writeHosts("ghe.example.com:\n    users:\n        dave:\n    user: dave\n")
        _ = await reload(discovery)
        gated.open()
        #expect(await refreshed == nil)
        #expect(await fixture.credentials.token(for: alice) == nil)
    }

    @Test func stopsGhWhenTheOnlyCallerIsCancelled() async throws {
        try fixture.writeHosts(twoAccounts)
        let gated = GatedProcessRunner(base: fixture.runner)
        let discovery = fixture.discovery(runner: gated)
        _ = await reload(discovery)
        gated.close()
        let refresh = Task { await discovery.refreshToken(for: alice) }
        await gated.waitUntilWaiting(1)
        refresh.cancel()
        gated.open()
        #expect(await refresh.value == nil)
    }

    @Test func keepsGhRunningForAJoinedCallerWhenTheFirstIsCancelled() async throws {
        try fixture.writeHosts(twoAccounts)
        let gated = GatedProcessRunner(base: fixture.runner)
        let discovery = fixture.discovery(runner: gated)
        _ = await reload(discovery)
        gated.close()
        let refresh = Task { await discovery.refreshToken(for: alice) }
        await gated.waitUntilWaiting(1)
        async let reloaded = reload(discovery)
        await waitUntilAsync { await discovery.hasJoinedTokenFetch(for: alice) }
        refresh.cancel()
        gated.open()
        let states = await reloaded
        #expect(
            states.last
                == .accounts([status("github.com", "alice", .ready), status("ghe.example.com", "dave", .ready)]))
        #expect(await fixture.credentials.token(for: alice)?.value == "test-token-alice")
    }

    @Test func sharesARunningTokenFetchBetweenReloadAndRefresh() async throws {
        try fixture.writeHosts(twoAccounts)
        let gated = GatedProcessRunner(base: fixture.runner)
        let discovery = fixture.discovery(runner: gated)
        _ = await reload(discovery)
        await fixture.credentials.remove(alice)
        gated.close()
        async let reloaded = reload(discovery)
        await gated.waitUntilWaiting(1)
        async let refreshed = discovery.refreshToken(for: alice)
        await waitUntilAsync { await discovery.hasJoinedTokenFetch(for: alice) }
        // 合流していれば、2 つ目の gh は門の前に並ばない
        #expect(gated.waitingCount == 1)
        gated.open()
        let (states, token) = await (reloaded, refreshed)
        #expect(token?.value == "test-token-alice")
        #expect(states.last?.hasAccounts == true)
        #expect(fixture.tokenRequests.filter { $0.last == "alice" }.count == 2)
    }
}
