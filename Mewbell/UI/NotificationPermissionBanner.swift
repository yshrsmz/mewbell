import AppKit
import SwiftUI

/// macOS の通知が切られているときの案内。
struct NotificationPermissionBanner: View {
    /// システム設定の通知の画面
    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "bell.slash.fill")
                .foregroundStyle(.secondary)
            Text("Notifications are turned off for Mewbell.")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Open Settings") {
                if let url = Self.settingsURL {
                    NSWorkspace.shared.open(url)
                }
            }
            .controlSize(.small)
        }
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// メニューバーの猫アイコンの横に出す、未読の件数。
enum UnreadBadge {
    /// 0 件なら nil、100 件以上は `99+`。
    static func text(for count: Int) -> String? {
        switch count {
        case ...0: nil
        case 1...99: String(count)
        default: "99+"
        }
    }
}

/// メニューバーのラベル。猫アイコンと未読の件数を 1 つの `Text` にする
/// （`MenuBarExtra` のラベルは `HStack` を並べても画像しか出ないことがあるため）。
struct MenuBarLabel: View {
    let notifications: NotificationStore

    var body: some View {
        if let badge = UnreadBadge.text(for: notifications.unreadCount) {
            Text("\(Image(systemName: "cat.fill")) \(badge)")
                .accessibilityLabel("Mewbell, \(badge) unread")
        } else {
            Image(systemName: "cat.fill")
                .accessibilityLabel("Mewbell")
        }
    }
}

#Preview("Permission banner") {
    NotificationPermissionBanner()
        .padding()
        .frame(width: 380)
}
