import SwiftUI

/// アカウントのホストの Web の通知一覧を開くボタン。
struct OpenWebNotificationsButton: View {
    let host: String
    let action: () -> Void

    var body: some View {
        let label = "Open notifications on \(host)"
        Button(action: action) {
            Image(systemName: "arrow.up.forward.square")
        }
        .buttonStyle(HoverHighlightButtonStyle(padding: 0, outset: 4))
        .help(label)
        .accessibilityLabel(label)
    }
}
