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
