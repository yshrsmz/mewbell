import Foundation

/// `reason` の表示名（一覧と macOS の通知で使う）。
enum ThreadReason {
    private static let reasonTexts = [
        "assign": "Assigned",
        "author": "Author",
        "ci_activity": "CI activity",
        "comment": "Comment",
        "manual": "Subscribed",
        "mention": "Mentioned",
        "review_requested": "Review requested",
        "security_alert": "Security alert",
        "state_change": "State changed",
        "subscribed": "Watching",
        "team_mention": "Team mentioned",
    ]

    /// `reason` の表示名。知らない値は `_` を空白にして先頭を大文字にする。
    static func text(_ reason: String) -> String {
        reasonTexts[reason] ?? reason.replacing("_", with: " ").capitalizingFirstLetter
    }
}

extension String {
    fileprivate var capitalizingFirstLetter: String {
        prefix(1).uppercased() + dropFirst()
    }
}
