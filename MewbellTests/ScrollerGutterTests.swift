import AppKit
import Testing

@testable import Mewbell

@MainActor struct ScrollerGutterTests {
    private static var scrollerWidth: CGFloat { NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) }

    /// legacy でスクロールバーが出ていないとき（収まっている・アニメーションで隠している）だけ、スクロールバーの幅を空ける
    @Test(arguments: [
        (false, false, true),
        (true, false, false),
        (true, true, true),
        (false, true, true),
    ])
    func legacyReservesWidthWhileScrollerIsHidden(overflows: Bool, indicatorsHidden: Bool, reserves: Bool) throws {
        // 幅が 0 だと、空けるときと空けないときを見分けられない
        try #require(Self.scrollerWidth > 0)
        let gutter = ScrollerGutter(style: .legacy, overflows: overflows, indicatorsHidden: indicatorsHidden)
        #expect(gutter.width == (reserves ? Self.scrollerWidth : 0))
    }

    /// overlay のスクロールバーは中身に重なるので、どの状態でも空けない
    @Test(arguments: [(false, false), (true, false), (true, true)])
    func overlayReservesNothing(overflows: Bool, indicatorsHidden: Bool) {
        let gutter = ScrollerGutter(style: .overlay, overflows: overflows, indicatorsHidden: indicatorsHidden)
        #expect(gutter.width == 0)
    }
}
