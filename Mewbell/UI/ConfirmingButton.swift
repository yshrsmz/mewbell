import SwiftUI

/// 2 回押して実行するボタン。1 回目で確認の文の表示に変わり、5 秒以内にもう一度押したときだけ実行する。
/// 確認の状態は呼び出し側が持つ（コンテキストメニューなど、ボタンの外から確認の表示にできるように）。
/// 5 秒たったとき、押せなくなったとき、対象が変わったとき、消えたときは、実行せずに元の表示に戻す。
struct ConfirmingButton<Icon: View, Target: Equatable>: View {
    @Binding var confirming: Bool
    /// 元の表示
    let icon: Icon
    /// 確認の表示の文
    let confirmation: String
    /// ツールチップとアクセシビリティのラベル（呼び出し側が `confirming` に合わせて決める）
    let help: String
    let accessibilityLabel: String
    var isEnabled = true
    /// 操作の対象を表す値（件数と最新のスレッド、スレッドの ID など）。確認の途中で変わったら確認からやり直す
    let target: Target
    /// `HoverHighlightButtonStyle` の塗りのはみ出し
    var outset: CGFloat = 0
    let action: () -> Void

    var body: some View {
        Button {
            if confirming {
                confirming = false
                action()
            } else {
                confirming = true
            }
        } label: {
            if confirming {
                Text(confirmation)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                    .fixedSize()
            } else {
                icon
            }
        }
        .buttonStyle(HoverHighlightButtonStyle(outset: outset))
        .disabled(!isEnabled)
        .help(help)
        .accessibilityLabel(accessibilityLabel)
        // 確認の表示は 5 秒で戻す（`confirming` が変わると前の待ちは取り消される）
        .task(id: confirming) {
            guard confirming else { return }
            guard (try? await Task.sleep(for: .seconds(5))) != nil else { return }
            confirming = false
        }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled {
                confirming = false
            }
        }
        // 確認の途中で対象が変わったら、見ていないスレッドまで操作しないように確認からやり直す
        .onChange(of: target) { confirming = false }
        .onDisappear { confirming = false }
    }
}
