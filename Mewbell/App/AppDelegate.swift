import AppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let accountStore: AccountStore
    let notificationStore: NotificationStore
    let notificationPermission: NotificationPermission
    /// 通知センターの delegate（通知センターは delegate を弱く持つので、ここで持ち続ける）
    private let clickHandler: NotificationClickHandler?

    override init() {
        if LaunchContext.isTestHostOrPreview {
            accountStore = AccountStore(discovery: nil)
            notificationStore = NotificationStore(makePoller: nil)
            notificationPermission = NotificationPermission(center: nil)
            clickHandler = nil
        } else {
            let discovery = AccountDiscovery.live(credentials: CredentialStore())
            let center = LiveUserNotificationCenter()
            let notificationStore = NotificationStore.live(
                tokens: discovery, notifier: SystemNotifier(center: center))
            accountStore = AccountStore(discovery: discovery)
            self.notificationStore = notificationStore
            notificationPermission = NotificationPermission(center: center)
            clickHandler = NotificationClickHandler { request in
                notificationStore.openFromNotification(request)
            }
        }
        super.init()
        accountStore.onStateChange = { [notificationStore] state in
            notificationStore.sync(with: state)
        }
        // 終了中の通知のクリックで起動されたときに取りこぼさないよう、起動が終わる前に設定する
        if let clickHandler {
            UNUserNotificationCenter.current().delegate = clickHandler
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
