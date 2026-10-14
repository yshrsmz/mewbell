import SwiftUI

/// ポップオーバーの押せる要素（アイコンのボタン、スレッドの行、開閉の見出し）のスタイル。
/// ホバー中と押している間に、ラベルの後ろへ角丸の薄い塗りを付ける。押せないときは塗りを付けず、ラベルを薄くする。
struct HoverHighlightButtonStyle: ButtonStyle {
    /// 塗りの内側の余白。ボタンの枠も広がる。枠の大きさを決めてあるボタン、行と見出しは 0 にする
    var padding: CGFloat = 4
    /// 塗りを枠の外へはみ出させる幅。見出しや行の中に並べるボタンは、枠を広げると見出しの高さとほかの要素の位置が変わるので、
    /// 余白の代わりにこれで塗りを広げる
    var outset: CGFloat = 0
    /// ラベルの外も含めたホバーの状態を持つときに渡す（スレッドの行は、上に重ねた操作のボタンに載せている間も行を塗る）。
    /// nil のときは、ラベルに載せているかで決める
    var isHovering: Bool?

    func makeBody(configuration: Configuration) -> some View {
        HoverHighlight(configuration: configuration, padding: padding, outset: outset, externalHovering: isHovering)
    }

    private struct HoverHighlight: View {
        let configuration: ButtonStyleConfiguration
        let padding: CGFloat
        let outset: CGFloat
        let externalHovering: Bool?
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .padding(padding)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(.primary.opacity(backgroundOpacity))
                        .padding(-outset)
                )
                .contentShape(RoundedRectangle(cornerRadius: 5))
                .onHover { isHovering = $0 }
        }

        private var backgroundOpacity: Double {
            guard isEnabled else { return 0 }
            if configuration.isPressed { return 0.2 }
            return (externalHovering ?? isHovering) ? 0.08 : 0
        }
    }
}
