import AppKit
import Testing

@testable import Mewbell

@MainActor struct ListScrollerTests {
    /// スクロールバーが横に並ぶ表示では、一覧の幅からスクロールバーの幅を引いた幅を上限にする
    @Test func legacyLimitsToListWidthMinusScroller() throws {
        let scrollerWidth = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        // 幅が 0 だと、上限を付けたかどうかを見分けられない
        try #require(scrollerWidth > 0)
        #expect(ListScroller.contentWidthLimit(scrollerStyle: .legacy, listWidth: 348) == 348 - scrollerWidth)
    }

    /// 重なる表示と、一覧の幅をまだ測っていないときは上限を付けない
    @Test(arguments: [(NSScroller.Style.overlay, CGFloat?(348)), (.legacy, nil)])
    func noLimit(scrollerStyle: NSScroller.Style, listWidth: CGFloat?) {
        #expect(ListScroller.contentWidthLimit(scrollerStyle: scrollerStyle, listWidth: listWidth) == nil)
    }
}
