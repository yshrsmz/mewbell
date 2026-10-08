import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let accountStore = LaunchContext.isTestHostOrPreview ? AccountStore(discovery: nil) : AccountStore.live()

    func applicationDidFinishLaunching(_ notification: Notification) {
        accountStore.reload()
    }

    /// 終了する前に、メモリ上のトークンを捨てる。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await accountStore.discardCredentials()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
