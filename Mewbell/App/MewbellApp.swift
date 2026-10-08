import SwiftUI

@main
struct MewbellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // シーンを作る前に確かめ、二重起動したときにメニューバーのアイコンが増えないようにする
        SingleInstance.terminateIfAnotherInstanceIsRunning()
    }

    var body: some Scene {
        MenuBarExtra("Mewbell", systemImage: "cat.fill") {
            MenuBarContentView(store: appDelegate.accountStore, notifications: appDelegate.notificationStore)
        }
        .menuBarExtraStyle(.window)
    }
}
