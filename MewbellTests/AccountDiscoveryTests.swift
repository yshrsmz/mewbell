import Foundation
import Synchronization
import Testing

@testable import Mewbell

struct AccountTests {
    @Test(arguments: [
        ("github.com", HostKind.gitHubDotCom),
        ("GitHub.com", .gitHubDotCom),
        ("acme.ghe.com", .gheCloud),
        ("github.example.com", .enterpriseServer),
        ("ghe.com", .enterpriseServer),
    ])
    func classifiesHosts(_ host: String, _ kind: HostKind) {
        #expect(HostKind(host: host) == kind)
    }

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

struct CredentialStoreTests {
    private let alice = AccountID(host: "github.com", user: "alice")
    private let bob = AccountID(host: "github.com", user: "bob")
    private let token = AccessToken(ghOutput: Data("test-token".utf8))

    @Test func discardsOnlyTheAccountsThatAreGone() async throws {
        let store = CredentialStore()
        let token = try #require(token)
        await store.set(token, for: alice)
        await store.set(token, for: bob)
        await store.retainOnly([alice])
        #expect(await store.contains(alice))
        #expect(await !store.contains(bob))
    }

    @Test func removesEverything() async throws {
        let store = CredentialStore()
        await store.set(try #require(token), for: alice)
        await store.removeAll()
        #expect(await store.token(for: alice) == nil)
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

    func discovery(candidates: [String]? = nil) -> AccountDiscovery {
        let locator = GhLocator(
            candidates: candidates ?? [ghPath], runner: runner, environment: [:], loginShell: { nil })
        return AccountDiscovery(
            locator: locator, runner: runner, environment: [:], configDirectory: configDirectory,
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

/// `reload` が渡した状態を順に記録する。
final class StateRecorder: Sendable {
    private let states = Mutex<[DiscoveryState]>([])

    var all: [DiscoveryState] { states.withLock { $0 } }
    var last: DiscoveryState? { all.last }

    func record(_ state: DiscoveryState) {
        states.withLock { $0.append(state) }
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

    private func reload(_ discovery: AccountDiscovery) async -> StateRecorder {
        let recorder = StateRecorder()
        await discovery.reload { recorder.record($0) }
        return recorder
    }

    private func status(_ host: String, _ user: String, _ state: TokenState, active: Bool = true) -> AccountStatus {
        AccountStatus(account: Account(id: AccountID(host: host, user: user), isActive: active), tokenState: state)
    }

    @Test func reportsMissingGh() async {
        let recorder = await reload(fixture.discovery(candidates: ["/nonexistent/gh"]))
        #expect(recorder.last == .ghNotFound)
    }

    @Test func reportsAnOutdatedGh() async throws {
        fixture.setVersion("gh version 2.39.2 (2023-11-14)\n")
        try fixture.writeHosts(twoAccounts)
        let recorder = await reload(fixture.discovery())
        #expect(recorder.last == .ghOutdated(version: GhVersion(major: 2, minor: 39, patch: 2)))
        #expect(fixture.tokenRequests.isEmpty)
    }

    @Test func reportsNotLoggedInWithoutHostsFile() async {
        let recorder = await reload(fixture.discovery())
        #expect(recorder.last == .notLoggedIn)
    }

    @Test func reportsAnUnreadableHostsFile() async throws {
        try fixture.writeHosts("github.com: [unclosed")
        let recorder = await reload(fixture.discovery())
        #expect(recorder.last == .hostsFileUnreadable(path: fixture.configDirectory.appending(path: "hosts.yml").path))
    }

    @Test func reportsAnUnreadableHostsFileEvenWhenGhCannotStart() async throws {
        // gh は hosts.yml を解釈できないと --version でも失敗する
        fixture.setVersion("")
        try fixture.writeHosts("github.com: [unclosed")
        let recorder = await reload(fixture.discovery())
        #expect(recorder.last == .hostsFileUnreadable(path: fixture.configDirectory.appending(path: "hosts.yml").path))
    }

    @Test func fetchesTokensForEveryAccount() async throws {
        try fixture.writeHosts(twoAccounts)
        fixture.setFailing(["dave"])
        let recorder = await reload(fixture.discovery())
        #expect(
            recorder.all == [
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
        let recorder = await reload(discovery)
        #expect(
            recorder.last
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
        let recorder = await reload(discovery)
        #expect(recorder.last == .accounts([status("github.com", "alice", .ready)]))
        #expect(await fixture.credentials.contains(AccountID(host: "github.com", user: "alice")))
        #expect(await !fixture.credentials.contains(AccountID(host: "ghe.example.com", user: "dave")))
    }

    @Test func discardsEveryTokenWhenNoLongerLoggedIn() async throws {
        try fixture.writeHosts(twoAccounts)
        let discovery = fixture.discovery()
        _ = await reload(discovery)
        try FileManager.default.removeItem(at: fixture.configDirectory.appending(path: "hosts.yml"))
        let recorder = await reload(discovery)
        #expect(recorder.last == .notLoggedIn)
        #expect(await !fixture.credentials.contains(AccountID(host: "github.com", user: "alice")))
    }
}

/// 読み込みが呼ばれた回数を数え、`finish()` まで終わらない `AccountDiscovering`。
final class BlockingDiscovery: AccountDiscovering {
    private let calls = Mutex(0)
    private let gate = AsyncStream<Void>.makeStream()

    var callCount: Int { calls.withLock { $0 } }

    func reload(update: @escaping @Sendable (DiscoveryState) async -> Void) async {
        calls.withLock { $0 += 1 }
        for await _ in gate.stream { break }
        await update(.notLoggedIn)
    }

    func discardAllCredentials() async {}

    func finish() {
        gate.continuation.yield()
    }
}

@MainActor
struct AccountStoreTests {
    @Test func ignoresAReloadWhileOneIsRunning() async {
        let discovery = BlockingDiscovery()
        let store = AccountStore(discovery: discovery, state: .ghNotFound)
        store.reload()
        #expect(store.state == .checking)
        #expect(store.isReloading)
        store.reload()
        await Task.yield()
        discovery.finish()
        await store.waitForReload()
        #expect(discovery.callCount == 1)
        #expect(store.state == .notLoggedIn)
        #expect(!store.isReloading)
    }

    @Test func keepsTheListWhileReloading() {
        let discovery = BlockingDiscovery()
        let accounts = DiscoveryState.accounts([])
        let store = AccountStore(discovery: discovery, state: accounts)
        store.reload()
        #expect(store.state == accounts)
        discovery.finish()
    }

    @Test func doesNothingWithoutDiscovery() {
        let store = AccountStore(discovery: nil, state: .ghNotFound)
        store.reload()
        #expect(store.state == .ghNotFound)
        #expect(!store.isReloading)
    }
}
