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
    @Environment(\.dismiss) private var dismiss

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
        dismiss()
        NSApp.activate()
        openSettings()
        // 初めて開くときは `SettingsWindowActivator` が、ウィンドウができたときに前面に出す。すでにあるウィンドウは、ここで出す
        SettingsWindowActivator.bringToFront()
    }
}

/// 設定ウィンドウに入れて、ウィンドウに載ったときに Mewbell を前面にし、そのウィンドウをキーにする
/// （ポップオーバーから開くと、`LSUIElement` のアプリのウィンドウはほかのアプリの後ろに開くため）。
struct SettingsWindowActivator: NSViewRepresentable {
    /// 今の設定ウィンドウ
    private static weak var window: NSWindow?

    static func bringToFront() {
        guard let window else { return }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func makeNSView(context: Context) -> NSView {
        ActivatingView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ActivatingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            SettingsWindowActivator.window = window
            SettingsWindowActivator.bringToFront()
        }
    }
}

#Preview {
    VStack {
        OpenSettingsButton()
        OpenSettingsButton(style: .text)
    }
    .padding()
}
