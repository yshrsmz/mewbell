import Foundation
import Observation

/// Mewbell の設定の唯一の持ち主。変更のメソッドで保存してから、変更の種類ごとのコールバックを呼ぶ
/// （無効化と `participating` で取る行動が違うので、Observation の追跡ではなく明示的に伝える）。
@MainActor
@Observable
final class AppSettings {
    private(set) var notificationSound: Bool
    private(set) var ghExecutableOverride: String?
    private(set) var ghConfigDirectoryOverride: String?
    private(set) var accountPreferences: [AccountID: AccountPreferences]

    @ObservationIgnored private let storage: any SettingsStorage

    /// アカウントを有効（true）・無効（false）にした
    @ObservationIgnored var onAccountEnabledChange: ((AccountID, Bool) -> Void)?
    /// 「参加しているスレッドだけにする」を切り替えた
    @ObservationIgnored var onParticipatingChange: ((AccountID) -> Void)?
    /// macOS の通知を出す（true）・出さない（false）にした
    @ObservationIgnored var onNotificationsChange: ((AccountID, Bool) -> Void)?
    /// gh のパスの上書きを変えた
    @ObservationIgnored var onGhExecutableChange: (() -> Void)?
    /// gh の設定ディレクトリの上書きを変えた
    @ObservationIgnored var onGhConfigDirectoryChange: (() -> Void)?

    init(storage: any SettingsStorage) {
        self.storage = storage
        notificationSound = SettingsKey.bool(SettingsKey.notificationSound, in: storage, default: true)
        ghExecutableOverride = SettingsKey.path(SettingsKey.ghExecutableOverride, in: storage)
        ghConfigDirectoryOverride = SettingsKey.path(SettingsKey.ghConfigDirectoryOverride, in: storage)
        accountPreferences = SettingsKey.accounts(in: storage)
    }

    func preferences(for id: AccountID) -> AccountPreferences {
        accountPreferences[id] ?? .default
    }

    var disabledAccounts: Set<AccountID> {
        Set(accountPreferences.filter { !$0.value.isEnabled }.keys)
    }

    var ghOverrides: GhOverrides {
        GhOverrides(executablePath: ghExecutableOverride, configDirectory: ghConfigDirectoryOverride)
    }

    /// アカウントの読み直しに渡す、今の設定（`AccountStore` が読み直しのたびに読む）。
    var discoveryOptions: DiscoveryOptions {
        DiscoveryOptions(overrides: ghOverrides, disabled: disabledAccounts)
    }

    func setEnabled(_ enabled: Bool, for id: AccountID) {
        guard update(id, { $0.isEnabled = enabled }) else { return }
        onAccountEnabledChange?(id, enabled)
    }

    func setParticipatingOnly(_ participatingOnly: Bool, for id: AccountID) {
        guard update(id, { $0.participatingOnly = participatingOnly }) else { return }
        onParticipatingChange?(id)
    }

    func setNotifies(_ notifies: Bool, for id: AccountID) {
        guard update(id, { $0.notifies = notifies }) else { return }
        onNotificationsChange?(id, notifies)
    }

    func setNotificationSound(_ enabled: Bool) {
        guard notificationSound != enabled else { return }
        notificationSound = enabled
        storage.set(enabled, forKey: SettingsKey.notificationSound)
    }

    /// 同じパスで確定し直したときも読み直す（権限を直した後に、同じパスを確かめ直せるように）。
    func setGhExecutableOverride(_ path: String?) {
        let path = SettingsKey.normalizedPath(path)
        if ghExecutableOverride != path {
            ghExecutableOverride = path
            storage.set(path, forKey: SettingsKey.ghExecutableOverride)
        }
        onGhExecutableChange?()
    }

    /// 同じパスで確定し直したときも読み直す（権限を直した後に、同じパスを確かめ直せるように）。
    func setGhConfigDirectoryOverride(_ path: String?) {
        let path = SettingsKey.normalizedPath(path)
        if ghConfigDirectoryOverride != path {
            ghConfigDirectoryOverride = path
            storage.set(path, forKey: SettingsKey.ghConfigDirectoryOverride)
        }
        onGhConfigDirectoryChange?()
    }

    /// アカウントの設定を変えて保存する。変わらなければ false。
    private func update(_ id: AccountID, _ change: (inout AccountPreferences) -> Void) -> Bool {
        var preferences = preferences(for: id)
        let old = preferences
        change(&preferences)
        guard preferences != old else { return false }
        accountPreferences[id] = preferences == .default ? nil : preferences
        storage.set(SettingsKey.accountsValue(accountPreferences), forKey: SettingsKey.accounts)
        return true
    }
}
