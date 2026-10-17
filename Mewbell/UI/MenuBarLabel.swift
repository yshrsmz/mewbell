import AppKit
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

/// メニューバーのアイコンの画像。猫と件数を 1 枚に描く
/// （`MenuBarExtra` のラベルに画像と文字を渡すと、片方しか出ないことがあるため）。
@MainActor
enum MenuBarIcon {
    /// 猫と件数の間。
    private static let spacing: CGFloat = 3

    /// 読み上げの名前。
    static func accessibilityLabel(badge: String?) -> String {
        badge.map { "Mewbell, \($0) unread" } ?? "Mewbell"
    }

    /// 0 件（`badge == nil`）はテンプレート画像の猫。件数があれば、緑の猫の右に件数を描いた画像にする。
    /// 色は描くときの外観（メニューバーの外観）で決まる。
    static func image(badge: String?) -> NSImage {
        let pointSize = NSFont.menuBarFont(ofSize: 0).pointSize
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        let description = accessibilityLabel(badge: badge)
        guard let badge else {
            let cat = catSymbol(configuration, description: description)
            cat.isTemplate = true
            return cat
        }
        let green = catSymbol(configuration.applying(.init(paletteColors: [.systemGreen])), description: description)
        let font = NSFont.monospacedDigitSystemFont(ofSize: pointSize, weight: .regular)
        let text = NSAttributedString(string: badge, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        let textSize = text.size()
        let size = NSSize(
            width: ceil(green.size.width + spacing + textSize.width),
            height: ceil(max(green.size.height, textSize.height)))
        let image = NSImage(size: size, flipped: false) { rect in
            green.draw(
                in: NSRect(
                    x: 0, y: (rect.height - green.size.height) / 2, width: green.size.width,
                    height: green.size.height))
            // 数字には下がりが無いので、行の高さではなく数字の高さ（capHeight）で縦の中央に置く
            let baseline = (rect.height - font.capHeight) / 2
            text.draw(at: NSPoint(x: green.size.width + spacing, y: baseline + font.descender))
            return true
        }
        image.accessibilityDescription = description
        return image
    }

    private static func catSymbol(_ configuration: NSImage.SymbolConfiguration, description: String) -> NSImage {
        let base = NSImage(systemSymbolName: "cat.fill", accessibilityDescription: description) ?? NSImage()
        return base.withSymbolConfiguration(configuration) ?? base
    }
}

/// メニューバーのラベル。猫アイコンと未読の件数を描いた画像 1 枚にする。
struct MenuBarLabel: View {
    let notifications: NotificationStore

    var body: some View {
        let badge = UnreadBadge.text(for: notifications.unreadCount)
        Image(nsImage: MenuBarIcon.image(badge: badge))
            .accessibilityLabel(MenuBarIcon.accessibilityLabel(badge: badge))
    }
}
