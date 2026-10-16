import AppKit

/// 一覧のスクロールバーの分の幅。
enum ListScroller {
    /// 一覧の中身の幅の上限。スクロールバーが中身の横に並ぶ表示（legacy）では、スクロールバーが出ていてもいなくても
    /// 「一覧の幅 − スクロールバーの幅」にし、出し消しで中身の幅（と右端に揃えたボタンの位置）が変わらないようにする。
    /// 中身に重なる表示（overlay）と、一覧の幅をまだ測っていないときは上限を付けない（nil）。
    /// 上限なので、実際に見える幅がこれより狭ければ中身はそちらに合わせ、右端は切れない
    @MainActor static func contentWidthLimit(scrollerStyle: NSScroller.Style, listWidth: CGFloat?) -> CGFloat? {
        guard scrollerStyle == .legacy, let listWidth else { return nil }
        return max(0, listWidth - NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy))
    }
}
