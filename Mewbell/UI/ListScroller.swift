import AppKit
import SwiftUI

/// 一覧の中身の右に残す、スクロールバーの分の空き。
/// スクロールバーが中身の横に並ぶ表示（legacy）では、スクロールバーが出ていないときだけスクロールバーの幅を空け、
/// 出ているかどうかで中身の幅（と右端に揃えたボタンの位置）が変わらないようにする。中身に重なる表示（overlay）では空けない
@MainActor struct ScrollerGutter: Equatable {
    let width: CGFloat

    /// - Parameters:
    ///   - overflows: 中身がスクロールの領域からはみ出している（はみ出すときだけスクロールバーが出る）
    ///   - indicatorsHidden: 開閉のアニメーションの間でスクロールバーを隠している
    init(style: NSScroller.Style, overflows: Bool, indicatorsHidden: Bool) {
        let showsScroller = overflows && !indicatorsHidden
        width =
            style == .legacy && !showsScroller
            ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0
    }
}

/// 一覧のスクロールバーの表示。開閉のアニメーションの間はスクロールバーを出さず（一覧の高さが毎フレーム変わり、ちらつくため）、
/// 出ていないときは `ScrollerGutter` の空きを残す。
/// アニメーションの数を読むのをこの modifier に閉じ込め、開閉のたびに一覧全体が描き直されないようにする
struct ListScrollerModifier: ViewModifier {
    let animations: DisclosureAnimations

    @State private var overflows = false
    @State private var scrollerStyle = NSScroller.preferredScrollerStyle

    func body(content: Content) -> some View {
        let indicatorsHidden = animations.running > 0
        let gutter = ScrollerGutter(style: scrollerStyle, overflows: overflows, indicatorsHidden: indicatorsHidden)
        content
            .scrollIndicators(indicatorsHidden ? .never : .automatic)
            .contentMargins(.trailing, gutter.width, for: .scrollContent)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.height > geometry.containerSize.height
            } action: { _, newValue in
                overflows = newValue
            }
            // マウスをつないだ・外したときや、システム設定でスクロールバーの表示を変えたときに届く
            .onReceive(
                NotificationCenter.default.publisher(for: NSScroller.preferredScrollerStyleDidChangeNotification)
            ) { _ in
                scrollerStyle = NSScroller.preferredScrollerStyle
            }
            // ポップオーバーを開くたびに、終わりが届かずに残った数を捨てる
            .onAppear { animations.reset() }
    }
}
