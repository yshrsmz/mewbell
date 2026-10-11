import SwiftUI

/// 見出しの開閉のボタン。先頭に山形を置き、山形のツールチップとアクセシビリティの説明を `Expand` / `Collapse` で切り替える。
/// 見出しの中身の読み上げとツールチップは残す（ボタン全体のラベルやツールチップで上書きしない）。
/// 開閉には短いアニメーションを付けるが、「視差効果を減らす」がオンのときは付けない。
struct DisclosureButton<Label: View>: View {
    let isCollapsed: Bool
    /// ツールチップと説明に出す名前（`alice (github.com)`、`owner/name`）
    let name: String
    /// 畳むものが無いとき（トークンを取れない、取得の前など）は false。山形を出さず、押せなくする
    var isCollapsible = true
    /// 見出しの件数。畳んでいて 1 件以上のときだけ出す
    var count = 0
    let toggle: () -> Void
    @ViewBuilder let label: Label

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(DisclosureAnimations.self) private var animations: DisclosureAnimations?

    var body: some View {
        if isCollapsible {
            let hint = isCollapsed ? "Expand \(name)" : "Collapse \(name)"
            Button {
                if reduceMotion {
                    toggle()
                } else {
                    animations?.begin()
                    withAnimation(.snappy(duration: 0.2), completionCriteria: .removed, toggle) {
                        animations?.end()
                    }
                }
            } label: {
                HStack(spacing: ListLayout.spacing) {
                    DisclosureChevron(isCollapsed: isCollapsed)
                        .help(hint)
                    labelWithCount
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")
            .accessibilityHint(hint)
        } else {
            HStack(spacing: ListLayout.spacing) {
                // 山形の分の幅を空けて、ほかの見出しと字下げを揃える
                DisclosureChevron(isCollapsed: isCollapsed).hidden()
                labelWithCount
            }
        }
    }

    /// 見出しの中身と、畳んだときの件数。
    @ViewBuilder private var labelWithCount: some View {
        label
        if let shown = Self.shownCount(isCollapsed: isCollapsed, count: count) {
            CollapsedCount(count: shown)
        }
    }

    /// 見出しに出す件数。畳んでいて 1 件以上のときだけ出し、それ以外は nil
    static func shownCount(isCollapsed: Bool, count: Int) -> Int? {
        isCollapsed && count > 0 ? count : nil
    }
}

/// 動いている開閉のアニメーションの数。`DisclosureButton` が数え、一覧はアニメーションの間だけスクロールバーを隠す
/// （高さが毎フレーム変わり、そのたびにスクロールバーが出てちらつくため）。続けて押すとアニメーションが重なるので数で持つ
@MainActor @Observable final class DisclosureAnimations {
    private(set) var running = 0

    func begin() {
        running += 1
    }

    /// 0 より下げない（`reset` の後に、前のアニメーションの終わりが届いても崩れないように）
    func end() {
        running = max(0, running - 1)
    }

    /// 終わりが届かないまま残った数を捨てる（アニメーションの途中でポップオーバーを閉じたときなど）。
    /// 残るとスクロールバーが隠れたままになる
    func reset() {
        running = 0
    }
}

/// 一覧の字下げ。見出しの山形の幅と、山形と中身の間隔から決まる。
enum ListLayout {
    /// 見出しの山形の幅
    static let chevronWidth: CGFloat = 16
    /// 山形と見出しの中身の間隔
    static let spacing: CGFloat = 6
    /// 見出しの下に置く中身の字下げ（山形の幅と間隔の分）
    static let contentIndent = chevronWidth + spacing
    /// 省略記号「…」が 1 つ入る幅（`.subheadline` の文字）。ここまで縮めると、省略記号の無い切れた字が残らない
    static let ellipsisWidth: CGFloat = 16
}

extension View {
    /// 区画の中の補足の文（取得の状態、操作の失敗、トークンを取れないときの案内）の体裁。
    /// 文字の大きさを揃え、見出しの中身の字下げに合わせ、幅に合わせて折り返す
    func sectionNote() -> some View {
        font(.subheadline)
            .padding(.leading, ListLayout.contentIndent)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 開閉を示す山形。開いているときは下を向く。幅はスレッドの行の種類のアイコンと揃える。
private struct DisclosureChevron: View {
    let isCollapsed: Bool

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(isCollapsed ? 0 : 90))
            .frame(width: ListLayout.chevronWidth)
            .accessibilityHidden(true)
    }
}

/// 折りたたんだ見出しに出す件数。
private struct CollapsedCount: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
            .capsuleBadge(.secondary.opacity(0.15))
            .accessibilityLabel("\(count) unread")
    }
}

extension View {
    /// 見出しに添える小さなカプセル型のバッジ（「active」、折りたたんだときの件数）。幅が足りなくても省略しない。
    func capsuleBadge(_ fill: some ShapeStyle) -> some View {
        fixedSize()
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(fill, in: Capsule())
    }
}
