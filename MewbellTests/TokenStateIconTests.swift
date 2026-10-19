import Foundation
import SwiftUI
import Testing

@testable import Mewbell

struct TokenStateIconTests {
    /// 状態ごとの記号・色・名前。記号と色は変えず、「止まっている」と「トークンを取れない」は名前だけで読み分ける。
    /// 記号が nil なのは取得中だけ（`ProgressView` を出す）
    @Test(arguments: [
        (TokenState.fetching, FeedPhase?.none, String?.none, Color?.none, "Getting token"),
        (.ready, nil, "checkmark.circle.fill", .green, "Ready"),
        (.ready, .loading, "checkmark.circle.fill", .green, "Ready"),
        (.ready, .loaded(updatedAt: .distantPast), "checkmark.circle.fill", .green, "Ready"),
        (.ready, .retrying(nextAttempt: .distantFuture, rateLimited: true), "checkmark.circle.fill", .green, "Ready"),
        (.ready, .scopeInsufficient, "exclamationmark.triangle.fill", .yellow, "Stopped"),
        (.ready, .unauthorized, "exclamationmark.triangle.fill", .yellow, "Stopped"),
        (.unavailable, nil, "exclamationmark.triangle.fill", .yellow, "No token"),
        (.disabled, nil, "pause.circle", nil, "Disabled"),
    ])
    func showsTheState(
        _ tokenState: TokenState, _ phase: FeedPhase?, _ symbol: String?, _ color: Color?, _ label: String
    ) {
        let icon = TokenStateIcon(tokenState: tokenState, phase: phase)
        #expect(icon.symbol == symbol)
        #expect(icon.color == color)
        #expect(icon.label == label)
    }
}
