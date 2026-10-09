import Foundation

/// 設定の保存先。値は Bool・String・`[String: [String: Bool]]` だけを書く（トークンや URL は書かない）。
protocol SettingsStorage: AnyObject {
    func object(forKey key: String) -> Any?
    /// `value` が nil ならキーを消す。
    func set(_ value: Any?, forKey key: String)
}

/// アプリの UserDefaults（ドメインは Bundle ID）に保存する。
final class UserDefaultsStorage: SettingsStorage {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func object(forKey key: String) -> Any? {
        defaults.object(forKey: key)
    }

    func set(_ value: Any?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

/// メモリにだけ持つ（テストと SwiftUI プレビュー用）。
final class InMemorySettingsStorage: SettingsStorage {
    private(set) var values: [String: Any]

    init(values: [String: Any] = [:]) {
        self.values = values
    }

    func object(forKey key: String) -> Any? {
        values[key]
    }

    func set(_ value: Any?, forKey key: String) {
        values[key] = value
    }
}

/// アカウントごとの設定。
struct AccountPreferences: Sendable, Equatable {
    var isEnabled = true
    /// `participating=true` で取得する
    var participatingOnly = false
    /// macOS の通知を出す
    var notifies = true

    static let `default` = AccountPreferences()
}

/// 保存のキーと、保存した値の読み書き。読めない値は既定値として扱う。
enum SettingsKey {
    static let notificationSound = "notificationSound"
    static let ghExecutableOverride = "ghExecutableOverride"
    static let ghConfigDirectoryOverride = "ghConfigDirectoryOverride"
    static let accounts = "accounts"

    static let all: Set<String> = [notificationSound, ghExecutableOverride, ghConfigDirectoryOverride, accounts]

    private enum AccountField {
        static let enabled = "enabled"
        static let participatingOnly = "participatingOnly"
        static let notifications = "notifications"
    }

    /// `bool(forKey:)` は文字列の "YES" も真にするので、型を確かめて読む。
    static func bool(_ key: String, in storage: some SettingsStorage, default defaultValue: Bool) -> Bool {
        storage.object(forKey: key) as? Bool ?? defaultValue
    }

    /// 前後の空白を除いて空なら nil。
    static func path(_ key: String, in storage: some SettingsStorage) -> String? {
        normalizedPath(storage.object(forKey: key) as? String)
    }

    static func normalizedPath(_ path: String?) -> String? {
        guard let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// `<host>/<user>` として検証を通るキーと、Bool の値だけを読む。
    static func accounts(in storage: some SettingsStorage) -> [AccountID: AccountPreferences] {
        guard let stored = storage.object(forKey: accounts) as? [String: Any] else { return [:] }
        var result: [AccountID: AccountPreferences] = [:]
        for (key, value) in stored {
            guard let id = accountID(from: key), let fields = value as? [String: Any] else { continue }
            var preferences = AccountPreferences.default
            if let enabled = fields[AccountField.enabled] as? Bool { preferences.isEnabled = enabled }
            if let participating = fields[AccountField.participatingOnly] as? Bool {
                preferences.participatingOnly = participating
            }
            if let notifications = fields[AccountField.notifications] as? Bool { preferences.notifies = notifications }
            result[id] = preferences
        }
        return result
    }

    /// 既定値と同じアカウントは書かない。
    static func accountsValue(_ preferences: [AccountID: AccountPreferences]) -> [String: [String: Bool]]? {
        let entries = preferences.filter { $0.value != .default }
        guard !entries.isEmpty else { return nil }
        return Dictionary(
            uniqueKeysWithValues: entries.map { id, preferences in
                (
                    id.description,
                    [
                        AccountField.enabled: preferences.isEnabled,
                        AccountField.participatingOnly: preferences.participatingOnly,
                        AccountField.notifications: preferences.notifies,
                    ]
                )
            })
    }

    static func accountID(from key: String) -> AccountID? {
        let parts = key.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let host = String(parts[0]).lowercased()
        let user = String(parts[1])
        guard GhIdentifier.isValidHost(host), GhIdentifier.isValidUser(user) else { return nil }
        return AccountID(host: host, user: user)
    }
}
