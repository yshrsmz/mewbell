import SwiftUI

/// アカウントのホストの Web の通知一覧を開くボタン。
struct OpenWebNotificationsButton: View {
    let host: String
    let action: () -> Void

    var body: some View {
        let label = "Open notifications on \(host)"
        Button(action: action) {
            ActionIcon("arrow.up.forward")
        }
        .buttonStyle(HoverHighlightButtonStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}
