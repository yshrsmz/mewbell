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
        // gh の出力の文字列は持たない
        #expect(!String(reflecting: detection).contains("2024-11-14"))
        #expect(!String(reflecting: detection).contains("releases"))
    }

    @Test func keepsTheVersionWithoutRunningGhVersionAgain() async throws {
        try fixture.writeHosts(oneAccount)
        let discovery = fixture.discovery()
        _ = await reload(discovery)
        _ = await reload(discovery)
        #expect(versionRuns == 1)
        #expect(await discovery.ghDiagnostics().version == GhVersion(major: 2, minor: 62, patch: 0))
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
    }

    @Test func forgetsTheConfigDirectoryWhenTheOverrideIsUnusable() async throws {
        try fixture.writeHosts(oneAccount)
        let discovery = fixture.discovery()
        _ = await reload(discovery)
        let missing = fixture.directory.url.appending(path: "gh-old").path
        _ = await reload(discovery, DiscoveryOptions(overrides: GhOverrides(configDirectory: missing)))
        let detection = await discovery.ghDiagnostics()
        #expect(detection.executable != nil)
        #expect(detection.configDirectory == nil)
        #expect(detection.version == nil)
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

    @Test func publishesTheGhOfTheNewConfigDirectory() async {
        let discovery = BlockingDiscovery()
        discovery.ghDetection = detection
        let settings = AppSettings(storage: InMemorySettingsStorage())
        let store = AccountStore(discovery: discovery, settings: settings)
        discovery.finish()
        store.reload()
        await store.waitForReload()
        var work = detection
        work.configDirectory = GhConfigDirectory.Resolved(
            url: URL(filePath: "/Users/me/gh-work", directoryHint: .isDirectory), source: .override)
        discovery.ghDetection = work
        discovery.finish()
        store.ghConfigDirectoryChanged()
        await store.waitForReload()
        #expect(store.ghDetection == work)
    }

    @Test func readingTheGhDoesNotReload() async {
        let discovery = BlockingDiscovery()
        let store = AccountStore(discovery: discovery)
        _ = store.ghDetection
        _ = store.ghDetection
        #expect(discovery.callCount == 0)
        #expect(discovery.ghReadCount == 0)
    }
}
