import SwiftUI

/// ポップオーバーの再読み込みボタン。読み直しと取得の間は、同じ枠に読み込み中の表示を出して押せなくする。
struct ReloadButton: View {
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .frame(width: 16, height: 16)
        }
        .buttonStyle(PressableIconButtonStyle())
        .disabled(isLoading)
        .help("Reload gh accounts, resume stopped accounts, and refetch notifications now")
        .accessibilityLabel(isLoading ? "Reloading" : "Reload")
    }
}

/// 押している間とホバー中に、アイコンの後ろへ背景を付ける。
struct PressableIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressableIcon(configuration: configuration)
    }

    private struct PressableIcon: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(.primary.opacity(backgroundOpacity))
                )
                .contentShape(RoundedRectangle(cornerRadius: 5))
                .onHover { isHovering = $0 }
        }

        private var backgroundOpacity: Double {
            guard isEnabled else { return 0 }
            if configuration.isPressed { return 0.2 }
            return isHovering ? 0.08 : 0
        }
    }
}

#Preview("Idle") {
    ReloadButton(isLoading: false) {}
        .padding()
}

#Preview("Loading") {
    ReloadButton(isLoading: true) {}
        .padding()
}
