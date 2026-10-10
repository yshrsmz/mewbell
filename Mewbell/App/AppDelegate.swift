import AppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings: AppSettings
    let launchAtLogin: LaunchAtLogin
    let accountStore: AccountStore
    let notificationStore: NotificationStore
    let notificationPermission: NotificationPermission
    /// 一覧の折りたたみ（起動している間だけ覚える）
    let listExpansion: ListExpansion
    /// 通知センターの delegate（通知センターは delegate を弱く持つので、ここで持ち続ける）
    private let clickHandler: NotificationClickHandler?

    override init() {
        let listExpansion = ListExpansion()
        self.listExpansion = listExpansion
        if LaunchContext.isTestHostOrPreview {
            settings = AppSettings(storage: InMemorySettingsStorage())
            launchAtLogin = LaunchAtLogin(service: InertLoginItem())
            accountStore = AccountStore(discovery: nil)
            notificationStore = NotificationStore(makePoller: nil, openURL: { _ in })
            notificationPermission = NotificationPermission(center: nil)
            clickHandler = nil
        } else {
            let settings = AppSettings(storage: UserDefaultsStorage())
            launchAtLogin = LaunchAtLogin(service: MainAppLoginItem())
            let discovery = AccountDiscovery.live(credentials: CredentialStore())
            let center = LiveUserNotificationCenter()
            let notifier = SystemNotifier(
                center: center, notifies: { settings.preferences(for: $0).notifies },
                playsSound: { settings.notificationSound })
            let notificationStore = NotificationStore.live(tokens: discovery, notifier: notifier, settings: settings)
            notifier.onNewThreads = { [listExpansion] account, threads in
                listExpansion.expand(account: account, repositories: Set(threads.map(\.repository)))
            }
            settings.onNotificationsChange = { id, notifies in
                if !notifies {
                    notifier.notificationsDisabled(id)
                }
            }
            self.settings = settings
            accountStore = AccountStore(discovery: discovery, settings: settings)
            self.notificationStore = notificationStore
            notificationPermission = NotificationPermission(center: center)
            clickHandler = NotificationClickHandler { request in
                notificationStore.openFromNotification(request)
            }
        }
        super.init()
        accountStore.onStateChange = { [notificationStore, listExpansion] state in
            notificationStore.sync(with: state)
            listExpansion.retain(Set(state.enabledStatuses.map(\.id)))
        }
        connectSettings()
        // 終了中の通知のクリックで起動されたときに取りこぼさないよう、起動が終わる前に設定する
        if let clickHandler {
            UNUserNotificationCenter.current().delegate = clickHandler
        }
    }

    /// 設定の変更を、アカウントの読み直しとポーラーに伝える。
    private func connectSettings() {
        settings.onAccountEnabledChange = { [accountStore] id, enabled in
            accountStore.setEnabled(enabled, for: id)
        }
        settings.onParticipatingChange = { [notificationStore] id in
            notificationStore.restart(id)
        }
        settings.onGhExecutableChange = { [accountStore] in
            accountStore.ghExecutableChanged()
        }
        settings.onGhConfigDirectoryChange = { [accountStore] in
            accountStore.ghConfigDirectoryChanged()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        notificationPermission.request()
        accountStore.reload()
    }

    /// 終了する前に、ポーリングを止めてメモリ上のトークンを捨てる。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        notificationStore.stopAll()
        Task {
            await accountStore.discardCredentials()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
