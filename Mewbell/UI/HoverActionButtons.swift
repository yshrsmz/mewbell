import SwiftUI

/// スレッドの行とリポジトリの見出しに、マウスを載せている間だけ重ねる「既読にする」「Done にする」のボタン。
/// 「Done にする」は、行ではすぐ実行するボタン、見出しでは 2 回押して実行するボタンなので、呼び出し側が渡す。
struct HoverActionButtons<Done: View>: View {
    /// 「既読にする」のツールチップとアクセシビリティのラベル
    let readLabel: String
    let markRead: () -> Void
    @ViewBuilder let done: Done

    var body: some View {
        HStack(spacing: 2) {
            Button(action: markRead) {
                ActionIcon("envelope.open")
            }
            .help(readLabel)
            .accessibilityLabel(readLabel)
            done
        }
        .buttonStyle(HoverHighlightButtonStyle())
        .padding(.horizontal, 2)
        // ボタンの間と左右のすき間を押しても、下の行や見出し（開く・折りたたむ）に届かないようにする
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {}
        }
    }
}

// `Done` によらない寸法と部品（`HoverActionButtons.titleFade` と書けるように、`EmptyView` の型に置く）
extension HoverActionButtons where Done == EmptyView {
    /// 行のボタンの大きさ（ボタン 2 つ、間隔 2、左右の余白 2 × 2）
    private static var rowSize: CGSize {
        CGSize(width: ListLayout.actionIconSize * 2 + 2 + 2 * 2, height: ListLayout.actionIconSize)
    }
    /// ボタンの手前で件名を薄くしていく幅
    private static var fadeWidth: CGFloat { 16 }

    /// スレッドの行のマスクから抜く形。ボタンの範囲を消し、その手前をだんだん薄くする
    /// （背景で隠すと、ポップオーバーの半透明の背景では下の文字が透けて見える）
    static var titleFade: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: fadeWidth)
            Color.black
                .frame(width: rowSize.width)
        }
        .frame(height: rowSize.height)
        .blendMode(.destinationOut)
    }
}
