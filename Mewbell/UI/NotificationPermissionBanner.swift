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
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Open Settings") {
                if let url = Self.settingsURL {
                    NSWorkspace.shared.open(url)
                }
            }
            .controlSize(.small)
        }
        .font(.subheadline)
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }
}

#Preview("Permission banner") {
    NotificationPermissionBanner()
        .padding()
        .frame(width: 380)
}
