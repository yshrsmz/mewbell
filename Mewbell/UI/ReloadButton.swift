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
            // 塗りの内側の余白
            .padding(4)
        }
        .buttonStyle(HoverHighlightButtonStyle())
        .disabled(isLoading)
        .help("Reload gh accounts, resume stopped accounts, and refetch notifications now")
        .accessibilityLabel(isLoading ? "Reloading" : "Reload")
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
