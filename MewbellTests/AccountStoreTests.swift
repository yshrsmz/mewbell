import Foundation
import Testing

@testable import Mewbell

@MainActor
struct AccountStoreTests {
    @Test func reportsStateChanges() async {
        let discovery = BlockingDiscovery()
        let store = AccountStore(discovery: discovery, state: .ghNotFound)
        let reported = LockedValue<[DiscoveryState]>([])
        store.onStateChange = { state in reported.withLock { $0.append(state) } }
        discovery.finish()
        discovery.finish()
        store.reload()
        await store.waitForReload()
        store.reload()
        await store.waitForReload()
        // 変わらなかった 2 回目は知らせない
        #expect(reported.value == [.notLoggedIn])
    }

    @Test func stopsReportingStateChangesAfterTermination() async {
        let discovery = BlockingDiscovery()
        let store = AccountStore(discovery: discovery, state: .ghNotFound)
        let reported = LockedValue<[DiscoveryState]>([])
        store.onStateChange = { state in reported.withLock { $0.append(state) } }
        store.reload()
        await store.discardCredentials()
        discovery.finish()
        await store.waitForReload()
        #expect(reported.value.isEmpty)
    }

    @Test func doesNotRunTwoReloadsAtOnce() async {
        let discovery = BlockingDiscovery()
        let store = AccountStore(discovery: discovery, state: .ghNotFound)
        store.reload(userInitiated: true)
        #expect(store.state == .checking)
        #expect(store.isReloading)
        store.reload()
        for _ in 0..<5 {
            await Task.yield()
        }
        #expect(discovery.callCount == 1)
        discovery.finish()
        discovery.finish()
        await store.waitForReload()
        #expect(discovery.callCount == 2)
        #expect(store.state == .notLoggedIn)
        #expect(!store.isReloading)
    }

    @Test func passesAQueuedUserReloadThrough() async {
        let discovery = BlockingDiscovery()
        let store = AccountStore(discovery: discovery)
        store.reload()
        store.reload(userInitiated: true)
        store.reload()
        discovery.finish()
        discovery.finish()
        await store.waitForReload()
        #expect(discovery.events.filter { $0.hasPrefix("reload(") || $0 == "reload" } == ["reload", "reload(user)"])
    }

    @Test func keepsTheGuidanceWhenReloadingWithoutProgress() {
        let discovery = BlockingDiscovery()
        let store = AccountStore(discovery: discovery, state: .ghNotFound)
        store.reload()
        #expect(store.state == .ghNotFound)
        discovery.finish()
    }

    @Test func keepsTheListWhileReloading() {
        let discovery = BlockingDiscovery()
        let accounts = DiscoveryState.accounts([])
        let store = AccountStore(discovery: discovery, state: accounts)
        store.reload()
        #expect(store.state == accounts)
        discovery.finish()
    }

    @Test func runsAQueuedReloadAfterTheCurrentOne() async {
        let discovery = BlockingDiscovery()
        let store = AccountStore(discovery: discovery)
        store.reload()
        store.reload()
        store.reload()
        discovery.finish()
        discovery.finish()
        await store.waitForReload()
        #expect(discovery.callCount == 2)
    }

    @Test func closesCredentialsAndRefusesToReloadWhenTerminating() async {
        let discovery = BlockingDiscovery()
        let store = AccountStore(discovery: discovery)
        store.reload()
        await store.discardCredentials()
        #expect(discovery.events.contains("closed"))
        discovery.finish()
        await store.waitForReload()
        store.reload()
        #expect(!store.isReloading)
        #expect(discovery.callCount == 1)
    }

    @Test func doesNothingWithoutDiscovery() {
        let store = AccountStore(discovery: nil, state: .ghNotFound)
        store.reload()
        #expect(store.state == .ghNotFound)
        #expect(!store.isReloading)
    }
}

@MainActor
struct AccountStoreSettingsTests {
    private let alice = Account(id: AccountID(host: "github.com", user: "alice"), isActive: true)
    private let bob = Account(id: AccountID(host: "github.com", user: "bob"), isActive: false)

    private func accounts(_ alice: TokenState, _ bob: TokenState) -> DiscoveryState {
        .accounts([
            AccountStatus(account: self.alice, tokenState: alice), AccountStatus(account: self.bob, tokenState: bob),
        ])
    }

    @Test func passesTheCurrentSettingsToEachReload() async {
        let discovery = BlockingDiscovery()
        let settings = AppSettings(storage: InMemorySettingsStorage())
        settings.setEnabled(false, for: bob.id)
        settings.setGhExecutableOverride("/Users/me/bin/gh")
        let store = AccountStore(discovery: discovery, settings: settings)
        discovery.finish()
        store.reload()
        await store.waitForReload()
        #expect(
            discovery.options == [
                DiscoveryOptions(overrides: GhOverrides(executablePath: "/Users/me/bin/gh"), disabled: [bob.id])
            ])
    }

    @Test func disablesAnAccountWithoutWaitingForAReload() async {
        let discovery = BlockingDiscovery()
        let settings = AppSettings(storage: InMemorySettingsStorage())
        let store = AccountStore(discovery: discovery, settings: settings, state: accounts(.ready, .ready))
        var reported: [DiscoveryState] = []
        store.onStateChange = { reported.append($0) }
        settings.setEnabled(false, for: bob.id)
        store.setEnabled(false, for: bob.id)
        #expect(store.state == accounts(.ready, .disabled))
        #expect(reported == [accounts(.ready, .disabled)])
        await waitUntil { discovery.events.contains("disable github.com/bob") }
        #expect(discovery.callCount == 0)
    }

    @Test func keepsADisabledAccountDisabledWhenAnOlderReloadFinishes() async {
        let discovery = BlockingDiscovery()
        discovery.result = accounts(.ready, .ready)
        let settings = AppSettings(storage: InMemorySettingsStorage())
        let store = AccountStore(discovery: discovery, settings: settings, state: accounts(.ready, .ready))
        store.reload()
        settings.setEnabled(false, for: bob.id)
        store.setEnabled(false, for: bob.id)
        discovery.finish()
        await store.waitForReload()
        #expect(store.state == accounts(.ready, .disabled))
    }

    @Test func reloadsWhenAnAccountIsEnabledAgain() async {
        let discovery = BlockingDiscovery()
        discovery.result = accounts(.ready, .ready)
        let settings = AppSettings(storage: InMemorySettingsStorage())
        let store = AccountStore(discovery: discovery, settings: settings, state: accounts(.ready, .disabled))
        discovery.finish()
        store.setEnabled(true, for: bob.id)
        await store.waitForReload()
        #expect(discovery.events.first == "reload")
        #expect(store.state == accounts(.ready, .ready))
    }

    @Test func reloadsAsTheUserWhenTheGhPathChanges() async {
        let discovery = BlockingDiscovery()
        let store = AccountStore(discovery: discovery, settings: AppSettings(storage: InMemorySettingsStorage()))
        discovery.finish()
        store.ghExecutableChanged()
        await store.waitForReload()
        #expect(discovery.events.first == "reload(user)")
    }

    @Test func discardsTokensAndIgnoresOlderReloadsWhenTheConfigDirectoryChanges() async {
        let discovery = BlockingDiscovery()
        discovery.result = accounts(.ready, .ready)
        let store = AccountStore(
            discovery: discovery, settings: AppSettings(storage: InMemorySettingsStorage()),
            state: accounts(.ready, .ready))
        var reported: [DiscoveryState] = []
        store.onStateChange = { reported.append($0) }
        store.reload()
        store.ghConfigDirectoryChanged()
        #expect(store.state == .checking)
        // 前の設定ディレクトリで始めた読み直しの結果（アカウントあり）は捨てる
        discovery.finish()
        await waitUntil { discovery.events.contains("reloadFinished") }
        discovery.result = .notLoggedIn
        discovery.finish()
        await store.waitForReload()
        #expect(reported == [.checking, .notLoggedIn])
        let events = discovery.events
        #expect(events == ["reload", "reloadFinished", "discardAll", "reload(user)", "reloadFinished"])
    }
}
