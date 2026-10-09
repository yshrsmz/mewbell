import Foundation
import Testing

@testable import Mewbell

@MainActor
struct SettingsStorageTests {
    private let alice = AccountID(host: "github.com", user: "alice")
    private let dave = AccountID(host: "acme.ghe.com", user: "dave")

    @Test func startsWithDefaults() {
        let settings = AppSettings(storage: InMemorySettingsStorage())
        #expect(settings.notificationSound)
        #expect(settings.ghExecutableOverride == nil)
        #expect(settings.ghConfigDirectoryOverride == nil)
        #expect(settings.preferences(for: alice) == .default)
        #expect(settings.disabledAccounts.isEmpty)
    }

    @Test func readsBackWhatWasWritten() {
        let storage = InMemorySettingsStorage()
        let settings = AppSettings(storage: storage)
        settings.setNotificationSound(false)
        settings.setGhExecutableOverride("/Users/me/bin/gh")
        settings.setGhConfigDirectoryOverride("/Users/me/.gh-work")
        settings.setEnabled(false, for: alice)
        settings.setParticipatingOnly(true, for: dave)
        settings.setNotifies(false, for: dave)

        let reread = AppSettings(storage: storage)
        #expect(!reread.notificationSound)
        #expect(reread.ghExecutableOverride == "/Users/me/bin/gh")
        #expect(reread.ghConfigDirectoryOverride == "/Users/me/.gh-work")
        #expect(reread.preferences(for: alice) == AccountPreferences(isEnabled: false))
        #expect(reread.preferences(for: dave) == AccountPreferences(participatingOnly: true, notifies: false))
        #expect(reread.disabledAccounts == [alice])
    }

    @Test func treatsMalformedValuesAsDefaults() {
        let storage = InMemorySettingsStorage(values: [
            SettingsKey.notificationSound: "NO",
            SettingsKey.ghExecutableOverride: 42,
            SettingsKey.accounts: [
                "github.com/alice": ["enabled": false],
                "--help/alice": ["enabled": false],
                "github.com/bob": ["enabled": "NO"],
                "nonsense": ["enabled": false],
                "github.com/carol": "enabled",
            ] as [String: Any],
        ])
        let settings = AppSettings(storage: storage)
        #expect(settings.notificationSound)
        #expect(settings.ghExecutableOverride == nil)
        #expect(settings.disabledAccounts == [alice])
        #expect(settings.preferences(for: AccountID(host: "github.com", user: "bob")) == .default)
    }

    @Test func removesAccountsBackAtTheirDefaults() {
        let storage = InMemorySettingsStorage()
        let settings = AppSettings(storage: storage)
        settings.setEnabled(false, for: alice)
        #expect(storage.values[SettingsKey.accounts] != nil)
        settings.setEnabled(true, for: alice)
        #expect(storage.values[SettingsKey.accounts] == nil)
    }

    @Test func removesBlankPathOverrides() {
        let storage = InMemorySettingsStorage()
        let settings = AppSettings(storage: storage)
        settings.setGhExecutableOverride("  /Users/me/bin/gh \n")
        #expect(settings.ghExecutableOverride == "/Users/me/bin/gh")
        settings.setGhExecutableOverride("   ")
        #expect(settings.ghExecutableOverride == nil)
        #expect(storage.values[SettingsKey.ghExecutableOverride] == nil)
    }

    @Test func userDefaultsStorageReadsMalformedValuesAsDefaults() throws {
        let suite = "MewbellTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("YES", forKey: SettingsKey.notificationSound)
        defaults.set(false, forKey: "unrelated")

        let settings = AppSettings(storage: UserDefaultsStorage(defaults: defaults))
        #expect(settings.notificationSound)
        settings.setNotificationSound(false)
        settings.setEnabled(false, for: alice)
        #expect(!AppSettings(storage: UserDefaultsStorage(defaults: defaults)).notificationSound)
        #expect(AppSettings(storage: UserDefaultsStorage(defaults: defaults)).disabledAccounts == [alice])
    }
}

@MainActor
struct AppSettingsTests {
    private let alice = AccountID(host: "github.com", user: "alice")

    @Test func callsOnlyTheMatchingCallbackOnce() {
        let settings = AppSettings(storage: InMemorySettingsStorage())
        var events: [String] = []
        settings.onAccountEnabledChange = { id, enabled in events.append("enabled \(id) \(enabled)") }
        settings.onParticipatingChange = { id in events.append("participating \(id)") }
        settings.onNotificationsChange = { id, notifies in events.append("notifies \(id) \(notifies)") }
        settings.onGhExecutableChange = { events.append("gh") }
        settings.onGhConfigDirectoryChange = { events.append("config") }

        settings.setEnabled(false, for: alice)
        settings.setEnabled(false, for: alice)
        settings.setParticipatingOnly(true, for: alice)
        settings.setParticipatingOnly(true, for: alice)
        settings.setNotifies(false, for: alice)
        settings.setNotifies(false, for: alice)
        settings.setNotificationSound(false)
        settings.setGhExecutableOverride("/Users/me/bin/gh")
        settings.setGhExecutableOverride("/Users/me/bin/gh ")
        settings.setGhConfigDirectoryOverride("/Users/me/.gh-work")
        settings.setGhConfigDirectoryOverride(nil)

        #expect(
            events == [
                "enabled github.com/alice false", "participating github.com/alice", "notifies github.com/alice false",
                "gh", "config", "config",
            ])
    }

    @Test func writesOnlyKnownKeysOfPlainTypes() {
        let storage = InMemorySettingsStorage()
        let settings = AppSettings(storage: storage)
        settings.setNotificationSound(false)
        settings.setGhExecutableOverride("/Users/me/bin/gh")
        settings.setGhConfigDirectoryOverride("/Users/me/.gh-work")
        settings.setEnabled(false, for: alice)
        settings.setParticipatingOnly(true, for: AccountID(host: "acme.ghe.com", user: "dave"))

        #expect(Set(storage.values.keys) == SettingsKey.all)
        #expect(storage.values[SettingsKey.notificationSound] is Bool)
        #expect(storage.values[SettingsKey.ghExecutableOverride] is String)
        #expect(storage.values[SettingsKey.ghConfigDirectoryOverride] is String)
        let accounts = storage.values[SettingsKey.accounts] as? [String: [String: Bool]]
        #expect(Set(accounts?.keys ?? [:].keys) == ["github.com/alice", "acme.ghe.com/dave"])
    }
}
