import SwiftUI

@main
struct MewbellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // シーンを作る前に確かめ、二重起動したときにメニューバーのアイコンが増えないようにする
        SingleInstance.terminateIfAnotherInstanceIsRunning()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(
                store: appDelegate.accountStore, notifications: appDelegate.notificationStore,
                permission: appDelegate.notificationPermission, settings: appDelegate.settings,
                expansion: appDelegate.listExpansion
            )
            // ラベルの表示で付けられなかったとき（ステータスアイテムが作り直されたときなど）も、ポップオーバーを開けば付け直す
            .modifier(AttachStatusItemMenu(menu: appDelegate.statusItemMenu))
        } label: {
            MenuBarLabel(notifications: appDelegate.notificationStore)
                .modifier(AttachStatusItemMenu(menu: appDelegate.statusItemMenu))
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                settings: appDelegate.settings, accounts: appDelegate.accountStore,
                notifications: appDelegate.notificationStore, launchAtLogin: appDelegate.launchAtLogin)
        }
    }
}

/// 表示されたときに、メニューバーのアイコンの右クリックのメニューをステータスアイテムのボタンに付ける。
/// `openSettings` はシーンの中でしか読めないので、ここで読んで AppKit のメニューに渡す。
private struct AttachStatusItemMenu: ViewModifier {
    /// テストのホストとプレビューでは nil（本物のステータスアイテムに触れない）
    let menu: StatusItemMenu?

    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content.onAppear {
            guard let menu, let button = StatusItemMenu.statusBarButton() else { return }
            menu.attach(to: button, openSettings: { SettingsWindowActivator.open(using: openSettings) })
        }
    }
}
