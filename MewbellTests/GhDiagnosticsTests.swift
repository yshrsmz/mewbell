import Foundation
import Testing

@testable import Mewbell

/// `AccountDiscovery` が記録する gh の検出の結果のテスト。
struct GhDiagnosticsTests {
    private let fixture: DiscoveryFixture
    private let oneAccount = "github.com:\n    users:\n        alice:\n    user: alice\n"

    init() throws {
        fixture = try DiscoveryFixture()
        fixture.setVersion("gh version 2.62.0 (2024-11-14)\nhttps://github.com/cli/cli/releases/tag/v2.62.0\n")
    }

    private func reload(_ discovery: AccountDiscovery, _ options: DiscoveryOptions = DiscoveryOptions()) async
        -> DiscoveryState?
    {
        let states = LockedValue<[DiscoveryState]>([])
        await discovery.reload(userInitiated: false, options: options) { state in
            states.withLock { $0.append(state) }
        }
        return states.value.last
    }

    private var versionRuns: Int {
        fixture.runner.requests.filter { $0.arguments == ["--version"] }.count
    }

    @Test func recordsTheGhAndTheConfigDirectory() async throws {
        try fixture.writeHosts(oneAccount)
        let discovery = fixture.discovery()
        _ = await reload(discovery)
        let detection = await discovery.ghDiagnostics()
        #expect(
            detection.executable
                == GhLocation(
                    url: try #require(ExecutableValidator.validate(fixture.ghPath)), source: .standardLocation))
        #expect(detection.version == GhVersion(major: 2, minor: 62, patch: 0))
        #expect(
            detection.configDirectory
                == GhConfigDirectory.Resolved(url: fixture.configDirectory, source: .defaultLocation))
    }

    @Test func forgetsTheGhWhenItIsGone() async throws {
        try fixture.writeHosts(oneAccount)
        let discovery = fixture.discovery()
        _ = await reload(discovery)
        try FileManager.default.removeItem(atPath: fixture.ghPath)
        #expect(await reload(discovery) == .ghNotFound)
        let detection = await discovery.ghDiagnostics()
        #expect(detection.executable == nil)
        #expect(detection.version == nil)
        #expect(detection.configDirectory == nil)
    }

    @Test func recordsAnOutdatedVersion() async throws {
        try fixture.writeHosts(oneAccount)
        fixture.setVersion("gh version 2.39.0 (2023-11-27)\n")
        let discovery = fixture.discovery()
        #expect(await reload(discovery) == .ghOutdated(version: GhVersion(major: 2, minor: 39, patch: 0)))
        #expect(await discovery.ghDiagnostics().version == GhVersion(major: 2, minor: 39, patch: 0))
        #expect(fixture.tokenRequests.isEmpty)
    }

    @Test func forgetsTheConfigDirectoryWhenTheOverrideIsUnusable() async throws {
        try fixture.writeHosts(oneAccount)
        let discovery = fixture.discovery()
        _ = await reload(discovery)
        let tokenRequests = fixture.tokenRequests.count
        let missing = fixture.directory.url.appending(path: "gh-old").path
        // 使えない上書きから既定の設定ディレクトリへ戻らない
        #expect(
            await reload(discovery, DiscoveryOptions(overrides: GhOverrides(configDirectory: missing)))
                == .hostsFileUnreadable(path: missing + "/hosts.yml"))
        #expect(fixture.tokenRequests.count == tokenRequests)
        let detection = await discovery.ghDiagnostics()
        #expect(detection.executable != nil)
        #expect(detection.configDirectory == nil)
        // 同じ gh は確かめ済みなので、バージョンは出す
        #expect(detection.version == GhVersion(major: 2, minor: 62, patch: 0))
    }

    @Test func keepsTheVerifiedVersionWhenHostsFileIsUnreadable() async throws {
        try fixture.writeHosts(oneAccount)
        let discovery = fixture.discovery()
        _ = await reload(discovery)
        try fixture.writeHosts("github.com: [unterminated")
        #expect(
            await reload(discovery)
                == .hostsFileUnreadable(path: fixture.configDirectory.appending(path: "hosts.yml").path))
        let detection = await discovery.ghDiagnostics()
        #expect(detection.version == GhVersion(major: 2, minor: 62, patch: 0))
        #expect(detection.configDirectory?.source == .defaultLocation)
        #expect(versionRuns == 1)
    }

    @Test func recordsAnOverriddenConfigDirectory() async throws {
        try fixture.directory.makeFile("gh-work/hosts.yml", contents: oneAccount, permissions: 0o600)
        let work = fixture.directory.url.appending(path: "gh-work").path
        let discovery = fixture.discovery()
        _ = await reload(discovery, DiscoveryOptions(overrides: GhOverrides(configDirectory: work)))
        let detection = await discovery.ghDiagnostics()
        #expect(detection.configDirectory?.source == .override)
        #expect(detection.configDirectory?.url == ConfigDirectoryValidator.validate(work))
    }
}

@MainActor
struct AccountStoreGhDiagnosticsTests {
    private let detection = GhDiagnostics(
        executable: GhLocation(url: URL(filePath: "/opt/homebrew/bin/gh"), source: .standardLocation),
        version: GhVersion(major: 2, minor: 62, patch: 0),
        configDirectory: GhConfigDirectory.Resolved(
            url: URL(filePath: "/Users/me/.config/gh", directoryHint: .isDirectory), source: .defaultLocation))

    @Test func publishesTheGhAfterEachReload() async {
        let discovery = BlockingDiscovery()
        discovery.ghDetection = detection
        let store = AccountStore(discovery: discovery)
        #expect(store.ghDetection == GhDiagnostics())
        discovery.finish()
        store.reload()
        await store.waitForReload()
        #expect(store.ghDetection == detection)
    }
}
