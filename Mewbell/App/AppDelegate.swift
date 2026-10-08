import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let accountStore: AccountStore
    let notificationStore: NotificationStore

    override init() {
        if LaunchContext.isTestHostOrPreview {
            accountStore = AccountStore(discovery: nil)
            notificationStore = NotificationStore(makePoller: nil)
        } else {
            let credentials = CredentialStore()
            let discovery = AccountDiscovery.live(credentials: credentials)
            accountStore = AccountStore(discovery: discovery)
            notificationStore = NotificationStore.live(
                tokens: LiveTokenProvider(credentials: credentials, discovery: discovery))
        }
        super.init()
        accountStore.onStateChange = { [notificationStore] state in
            notificationStore.sync(with: state)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
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
