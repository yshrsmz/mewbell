import Foundation
import Testing

@testable import Mewbell

/// 設定（gh の上書きと無効なアカウント）を渡したときの `AccountDiscovery`。
struct AccountDiscoverySettingsTests {
    private let fixture: DiscoveryFixture
    private let alice = AccountID(host: "github.com", user: "alice")
    private let dave = AccountID(host: "ghe.example.com", user: "dave")
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

    private func reload(_ discovery: AccountDiscovery, _ options: DiscoveryOptions) async -> [DiscoveryState] {
        let states = LockedValue<[DiscoveryState]>([])
        await discovery.reload(userInitiated: false, options: options) { state in
            states.withLock { $0.append(state) }
        }
        return states.value
    }

    private func status(_ id: AccountID, _ state: TokenState) -> AccountStatus {
        AccountStatus(account: Account(id: id, isActive: true), tokenState: state)
    }

    private func realPath(_ path: String) -> String? {
        guard let pointer = realpath(path, nil) else { return nil }
        defer { free(pointer) }
        return String(cString: pointer)
    }

    // MARK: - gh のパスの上書き

    @Test func usesTheOverriddenGhPath() async throws {
        try fixture.writeHosts(twoAccounts)
        let other = try fixture.directory.makeFile("other/gh")
        let states = await reload(
            fixture.discovery(), DiscoveryOptions(overrides: GhOverrides(executablePath: other)))
        #expect(states.last?.hasAccounts == true)
        let executables = Set(fixture.runner.requests.map(\.executable.path))
        #expect(executables == [realPath(other)])
    }

    // MARK: - 設定ディレクトリの上書き

    @Test func readsTheOverriddenConfigDirectoryAndPassesItToGh() async throws {
        // 既定の設定ディレクトリには dave だけ、上書きした方には alice だけ
        try fixture.writeHosts("ghe.example.com:\n    users:\n        dave:\n    user: dave\n")
        let work = fixture.directory.url.appending(path: "gh-work")
        try fixture.directory.makeFile(
            "gh-work/hosts.yml", contents: "github.com:\n    users:\n        alice:\n    user: alice\n",
            permissions: 0o600)
        let discovery = fixture.discovery()
        let states = await reload(discovery, DiscoveryOptions(overrides: GhOverrides(configDirectory: work.path)))
        #expect(states.last == .accounts([status(alice, .ready)]))
        #expect(!fixture.runner.requests.isEmpty)
        // 確かめた実体のパス（`/var` → `/private/var`）を渡す
        let resolved = try #require(realPath(work.path))
        for request in fixture.runner.requests {
            #expect(request.environment["GH_CONFIG_DIR"] == resolved)
        }

        // 401 の後の取り直しも同じ設定ディレクトリで実行する
        _ = await discovery.refreshToken(for: alice)
        #expect(fixture.runner.requests.last?.arguments.last == "alice")
        #expect(fixture.runner.requests.last?.environment["GH_CONFIG_DIR"] == resolved)
    }

    @Test func doesNotPassGhConfigDirWithoutAnOverride() async throws {
        try fixture.writeHosts(twoAccounts)
        _ = await reload(fixture.discovery(), DiscoveryOptions())
        #expect(fixture.runner.requests.allSatisfy { $0.environment["GH_CONFIG_DIR"] == nil })
    }

    // MARK: - 無効なアカウント

    @Test func skipsDisabledAccounts() async throws {
        try fixture.writeHosts(twoAccounts)
        let discovery = fixture.discovery()
        let states = await reload(discovery, DiscoveryOptions(disabled: [dave]))
        #expect(
            states == [
                .accounts([status(alice, .fetching), status(dave, .disabled)]),
                .accounts([status(alice, .ready), status(dave, .disabled)]),
            ])
        #expect(fixture.tokenRequests.allSatisfy { $0.last != "dave" })
        #expect(await discovery.refreshToken(for: dave) == nil)
        #expect(fixture.tokenRequests.allSatisfy { $0.last != "dave" })
    }

    @Test func discardsTheTokenOfADisabledAccount() async throws {
        try fixture.writeHosts(twoAccounts)
        let discovery = fixture.discovery()
        _ = await reload(discovery, DiscoveryOptions())
        await discovery.disable(dave)
        #expect(await fixture.credentials.token(for: dave) == nil)
        #expect(await discovery.currentToken(for: dave) == nil)
        #expect(await discovery.refreshToken(for: dave) == nil)
        #expect(await fixture.credentials.token(for: alice) != nil)

        // 読み直しでも、無効なアカウントのトークンは取らない
        let states = await reload(discovery, DiscoveryOptions(disabled: [dave]))
        #expect(states.last == .accounts([status(alice, .ready), status(dave, .disabled)]))
        #expect(fixture.tokenRequests.filter { $0.last == "dave" }.count == 1)
    }

    @Test func doesNotStoreATokenFetchedWhileDisabling() async throws {
        try fixture.writeHosts(twoAccounts)
        let gated = GatedProcessRunner(base: fixture.runner)
        let discovery = fixture.discovery(runner: gated)
        _ = await reload(discovery, DiscoveryOptions())
        gated.close()
        async let refreshed = discovery.refreshToken(for: dave)
        await gated.waitUntilWaiting(1)
        await discovery.disable(dave)
        gated.open()
        #expect(await refreshed == nil)
        #expect(await fixture.credentials.token(for: dave) == nil)
    }

    @Test func discardsEveryToken() async throws {
        try fixture.writeHosts(twoAccounts)
        let discovery = fixture.discovery()
        _ = await reload(discovery, DiscoveryOptions())
        await discovery.discardAllTokens()
        #expect(await fixture.credentials.token(for: alice) == nil)
        #expect(await fixture.credentials.token(for: dave) == nil)
    }
}

/// 読み直しの途中の無効化と、設定ディレクトリの切り替え。
struct AccountDiscoveryRaceTests {
    private let fixture: DiscoveryFixture
    private let alice = AccountID(host: "github.com", user: "alice")
    private let dave = AccountID(host: "ghe.example.com", user: "dave")

    init() throws {
        fixture = try DiscoveryFixture()
        try fixture.writeHosts(
            """
            github.com:
                users:
                    alice:
                user: alice
            ghe.example.com:
                users:
                    dave:
                user: dave
            """)
    }

    @Test func keepsAnAccountDisabledDuringAReloadThatStartedBefore() async throws {
        let gated = GatedProcessRunner(base: fixture.runner, gating: "--version")
        let discovery = fixture.discovery(runner: gated)
        gated.close()
        let states = LockedValue<[DiscoveryState]>([])
        async let reloaded: Void = discovery.reload(userInitiated: false, options: DiscoveryOptions()) { state in
            states.withLock { $0.append(state) }
        }
        await gated.waitUntilWaiting(1)
        // 古い設定で始めた読み直しが `gh --version` を待っている間に無効にする
        await discovery.disable(dave)
        gated.open()
        await reloaded
        #expect(fixture.tokenRequests.allSatisfy { $0.last != "dave" })
        #expect(await fixture.credentials.token(for: dave) == nil)
        #expect(
            states.value.last
                == .accounts([
                    AccountStatus(account: Account(id: alice, isActive: true), tokenState: .ready),
                    AccountStatus(account: Account(id: dave, isActive: true), tokenState: .disabled),
                ]))
    }

    @Test func doesNotReuseOrStoreATokenFetchStartedBeforeTheConfigDirectoryChanged() async throws {
        let gated = GatedProcessRunner(base: fixture.runner)
        let discovery = fixture.discovery(runner: gated)
        await discovery.reload(userInitiated: false, options: DiscoveryOptions()) { _ in }
        gated.close()
        async let refreshed = discovery.refreshToken(for: alice)
        await gated.waitUntilWaiting(1)
        await discovery.discardAllTokens()
        // 新しい読み直しは、走っている取得に合流せずに gh を実行し直す
        async let reloaded: Void = discovery.reload(userInitiated: false, options: DiscoveryOptions()) { _ in }
        await gated.waitUntilWaiting(3)
        gated.open()
        #expect(await refreshed == nil)
        await reloaded
        // 止めた古い取得の gh は実行されず、新しい読み直しの取得だけが走る
        #expect(fixture.tokenRequests.filter { $0.last == "alice" }.count == 2)
        #expect(await fixture.credentials.token(for: alice) != nil)
    }

    @Test func keepsADisableThatArrivedBeforeAReloadWithOlderSettings() async throws {
        let discovery = fixture.discovery()
        await discovery.reload(userInitiated: false, options: DiscoveryOptions()) { _ in }
        await discovery.disable(dave)
        // 無効にする前の設定で作った読み直しが後から届いても、dave は無効のまま
        await discovery.reload(userInitiated: false, options: DiscoveryOptions()) { _ in }
        #expect(await fixture.credentials.token(for: dave) == nil)
        #expect(fixture.tokenRequests.filter { $0.last == "dave" }.count == 1)
        // 有効にし直すと、次の読み直しで取る
        await discovery.enable(dave)
        await discovery.reload(userInitiated: false, options: DiscoveryOptions()) { _ in }
        #expect(await fixture.credentials.token(for: dave) != nil)
    }

    @Test func doesNotReportAnAccountEnabledDuringTheFetchAsReady() async throws {
        let gated = GatedProcessRunner(base: fixture.runner)
        let discovery = fixture.discovery(runner: gated)
        await discovery.disable(dave)
        gated.close()
        let states = LockedValue<[DiscoveryState]>([])
        async let reloaded: Void = discovery.reload(userInitiated: false, options: DiscoveryOptions(disabled: [dave])) {
            state in states.withLock { $0.append(state) }
        }
        await gated.waitUntilWaiting(1)
        // alice のトークンを取っている間に dave を有効に戻す
        await discovery.enable(dave)
        gated.open()
        await reloaded
        #expect(
            states.value.last
                == .accounts([
                    AccountStatus(account: Account(id: alice, isActive: true), tokenState: .ready),
                    AccountStatus(account: Account(id: dave, isActive: true), tokenState: .disabled),
                ]))
        #expect(await fixture.credentials.token(for: dave) == nil)
    }
}
