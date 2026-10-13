import SwiftUI

/// アカウントの見出しのトークンの状態のアイコン。トークンの状態と、取得が止まっているかから決める。
/// 「止まっている」と「トークンを取れない」は同じ記号と色なので、名前で区別する。
struct TokenStateIcon {
    /// nil なら取得中（`ProgressView` を出す）
    let symbol: String?
    /// nil なら補足の色（`.secondary`）
    let color: Color?
    /// VoiceOver とツールチップに出す名前
    let label: String

    init(tokenState: TokenState, phase: FeedPhase?) {
        switch tokenState {
        case .fetching:
            (symbol, color, label) = (nil, nil, "Getting token")
        case .ready where phase?.isStopped == true:
            // トークンは持っているが、API に使えなかった
            (symbol, color, label) = ("exclamationmark.triangle.fill", .yellow, "Stopped")
        case .ready:
            (symbol, color, label) = ("checkmark.circle.fill", .green, "Ready")
        case .unavailable:
            (symbol, color, label) = ("exclamationmark.triangle.fill", .yellow, "No token")
        case .disabled:
            (symbol, color, label) = ("pause.circle", nil, "Disabled")
        }
    }
}
