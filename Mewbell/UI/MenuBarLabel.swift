import SwiftUI

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
