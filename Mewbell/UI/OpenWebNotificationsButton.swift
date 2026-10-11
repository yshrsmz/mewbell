import SwiftUI

/// アカウントのホストの Web の通知一覧を開くボタン。
struct OpenWebNotificationsButton: View {
    let host: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.forward.square")
        }
        .buttonStyle(.borderless)
        .help("Open notifications on \(host)")
        .accessibilityLabel("Open notifications on \(host)")
    }
}
