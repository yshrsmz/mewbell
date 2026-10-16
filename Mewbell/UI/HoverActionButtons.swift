import SwiftUI

/// スレッドの行とリポジトリ・アカウントの見出しに、マウスを載せている間だけ重ねるボタンの並び。
/// ボタンは呼び出し側が渡す（行とリポジトリの見出しは「既読にする」と「Done にする」、
/// アカウントの見出しは Web の通知一覧、すべて既読、すべて Done）。
struct HoverActionButtons<Buttons: View>: View {
    @ViewBuilder let buttons: Buttons

    var body: some View {
        HStack(spacing: 2) {
            buttons
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

// ボタンによらない寸法と部品（`HoverActionButtons.titleFade` と書けるように、`EmptyView` の型に置く）
extension HoverActionButtons where Buttons == EmptyView {
    /// 行のボタンの大きさ（ボタン 2 つ、間隔 2、左右の余白 2 × 2）
    private static var rowSize: CGSize {
        CGSize(width: ListLayout.actionIconSize * 2 + 2 + 2 * 2, height: ListLayout.actionIconSize)
    }
    /// ボタンの手前で件名を薄くしていく幅
    private static var fadeWidth: CGFloat { 16 }

    /// スレッドの行とリポジトリの見出しの、すぐ既読にする「既読にする」のボタン。
    /// `label` はツールチップとアクセシビリティのラベル
    static func markReadButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ActionIcon("envelope.open")
        }
        .help(label)
        .accessibilityLabel(label)
    }

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

extension View {
    /// 見出しの右端に、ホバーのボタンの並びを重ねる。ボタンは常に並べて幅を測っておき、出さないときは見えず・押せず・
    /// 読まれないようにする（出してから測ると、最初のホバーの 1 フレームだけ、見出しの中身がボタンに重なる）。
    /// 測った幅は `width` に入れる。見出しの中身は、ボタンを出している間はその幅の手前で省略する
    func headingActions<Buttons: View>(
        isShown: Bool, width: Binding<CGFloat>, @ViewBuilder buttons: () -> Buttons
    ) -> some View {
        overlay(alignment: .trailing) {
            HoverActionButtons(buttons: buttons)
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.width
                } action: {
                    width.wrappedValue = $0
                }
                .opacity(isShown ? 1 : 0)
                .allowsHitTesting(isShown)
                .accessibilityHidden(!isShown)
        }
    }
}
