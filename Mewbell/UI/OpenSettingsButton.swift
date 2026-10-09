import AppKit
import SwiftUI

/// 設定ウィンドウを開くボタン。`LSUIElement` のアプリは前面に出さないと、設定ウィンドウがほかのアプリの後ろに開くので、
/// 先に Mewbell を前面にする。ポップオーバーはキーウィンドウでなくなると閉じる。
struct OpenSettingsButton: View {
    enum Style {
        /// ポップオーバーの見出しの歯車
        case icon
        /// 案内の中の文字のボタン
        case text
    }

    var style: Style = .icon

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        switch style {
        case .icon:
            Button(action: open) {
                Image(systemName: "gearshape")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(PressableIconButtonStyle())
            .keyboardShortcut(",")
            .help("Settings")
            .accessibilityLabel("Settings")
        case .text:
            Button("Open Settings…", action: open)
        }
    }

    private func open() {
        NSApp.activate()
        openSettings()
    }
}

#Preview {
    VStack {
        OpenSettingsButton()
        OpenSettingsButton(style: .text)
    }
    .padding()
}
