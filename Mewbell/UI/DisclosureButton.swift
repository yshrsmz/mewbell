import SwiftUI

/// 見出しの開閉のボタン。先頭に山形を置き、山形のツールチップとアクセシビリティの説明を `Expand` / `Collapse` で切り替える。
/// 見出しの中身の読み上げとツールチップは残す（ボタン全体のラベルやツールチップで上書きしない）。
/// 開閉には短いアニメーションを付けるが、「視差効果を減らす」がオンのときは付けない。
struct DisclosureButton<Label: View>: View {
    let isCollapsed: Bool
    /// ツールチップと説明に出す名前（`alice (github.com)`、`owner/name`）
    let name: String
    /// 畳むものが無いとき（トークンを取れない、取得の前など）は false。山形を出さず、押せなくする
    var isEnabled = true
    let toggle: () -> Void
    @ViewBuilder let label: Label

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let hint = isCollapsed ? "Expand \(name)" : "Collapse \(name)"
        if isEnabled {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.2), toggle)
            } label: {
                HStack(spacing: 6) {
                    DisclosureChevron(isCollapsed: isCollapsed)
                        .help(hint)
                    label
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")
            .accessibilityHint(hint)
        } else {
            HStack(spacing: 6) {
                // 山形の分の幅を空けて、ほかの見出しと字下げを揃える
                DisclosureChevron(isCollapsed: isCollapsed).hidden()
                label
            }
        }
    }
}

/// 開閉を示す山形。開いているときは下を向く。幅はスレッドの行の種類のアイコンと揃える。
private struct DisclosureChevron: View {
    let isCollapsed: Bool

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(isCollapsed ? 0 : 90))
            .frame(width: 16)
            .accessibilityHidden(true)
    }
}

/// 折りたたんだ見出しに出す件数。
struct CollapsedCount: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .capsuleBadge(.secondary.opacity(0.15))
            .accessibilityLabel("\(count) unread")
    }
}

extension View {
    /// 見出しに添える小さなカプセル型のバッジ（「active」、折りたたんだときの件数）。
    func capsuleBadge(_ fill: some ShapeStyle) -> some View {
        padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(fill, in: Capsule())
    }
}
