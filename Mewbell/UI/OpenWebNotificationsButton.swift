import SwiftUI

/// アカウントのホストの Web の通知一覧を開くボタン。
struct OpenWebNotificationsButton: View {
    let host: String
    let action: () -> Void

    var body: some View {
        let label = Self.label(for: host)
        Button(action: action) {
            // 四角の枠から出ていく矢印は、外部へ開くことを表す慣用の形
            ActionIcon("arrow.up.forward.square")
        }
        .buttonStyle(HoverHighlightButtonStyle())
        .help(label)
        .accessibilityLabel(label)
    }

    /// ツールチップとアクセシビリティのラベル（開く先のホストを含める）
    static func label(for host: String) -> String {
        "Open notifications on \(host)"
    }
}
