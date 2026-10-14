import SwiftUI

/// ポップオーバーの押せる要素（アイコンのボタン、スレッドの行、開閉の見出し）のスタイル。
/// ホバー中と押している間に、ラベルの後ろへ角丸の薄い塗りを付ける。押せないときは塗りを付けず、ラベルを薄くする。
/// 塗りと押せる範囲はラベルの枠（四角形）に合わせる。塗りの内側に余白が要るボタンは、ラベルに余白を付ける。
struct HoverHighlightButtonStyle: ButtonStyle {
    /// 塗りと押せる範囲を枠の外へはみ出させる幅。並べる位置は変えない。見出しや行の中に並べるボタンは、
    /// 枠を広げると見出しの高さとほかの要素の位置が変わるので、余白の代わりにこれで広げる。隣と押せる範囲が重ならない幅にする
    var outset: CGFloat = 0
    /// ラベルの外も含めたホバーの状態を持つときに渡す（スレッドの行は、上に重ねた操作のボタンに載せている間も行を塗る）。
    /// nil のときは、ラベルに載せているかで決める
    var isHovering: Bool?

    func makeBody(configuration: Configuration) -> some View {
        HoverHighlight(configuration: configuration, style: self)
    }

    private struct HoverHighlight: View {
        let configuration: ButtonStyleConfiguration
        let style: HoverHighlightButtonStyle
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(isEnabled ? .primary : .tertiary)
                // 余白で広げて塗りと押せる範囲を付け、負の余白で並べる大きさを元に戻す
                .padding(style.outset)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(.primary.opacity(backgroundOpacity))
                )
                .contentShape(Rectangle())
                .onHover { isHovering = $0 }
                .padding(-style.outset)
                // 押せない間に外れたことが届かず、押せるようになったときに塗りが残らないように
                .onChange(of: isEnabled) { isHovering = false }
        }

        private var backgroundOpacity: Double {
            guard isEnabled else { return 0 }
            if configuration.isPressed { return 0.3 }
            return (style.isHovering ?? isHovering) ? 0.18 : 0
        }
    }
}
