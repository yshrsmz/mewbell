import Foundation

/// 1 つのリポジトリのスレッド。
struct RepositoryGroup: Identifiable, Equatable {
    let repository: RepositoryName
    /// 更新日時が新しい順
    let threads: [NotificationThread]

    var id: String { repository.description }
}

enum NotificationGrouping {
    /// リポジトリごとにまとめる。リポジトリは最新のスレッドの更新日時が新しい順、スレッドは更新日時が新しい順。
    static func groups(from threads: [NotificationThread]) -> [RepositoryGroup] {
        Dictionary(grouping: threads, by: \.repository)
            .map { repository, threads in
                RepositoryGroup(repository: repository, threads: threads.sorted(by: isNewer))
            }
            .sorted { lhs, rhs in
                let lhsDate = lhs.threads[0].updatedAt
                let rhsDate = rhs.threads[0].updatedAt
                return lhsDate != rhsDate ? lhsDate > rhsDate : lhs.id < rhs.id
            }
    }

    private static func isNewer(_ lhs: NotificationThread, _ rhs: NotificationThread) -> Bool {
        lhs.updatedAt != rhs.updatedAt ? lhs.updatedAt > rhs.updatedAt : lhs.id < rhs.id
    }

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
    static func reasonText(_ reason: String) -> String {
        reasonTexts[reason] ?? reason.replacing("_", with: " ").capitalizingFirstLetter
    }
}

extension String {
    fileprivate var capitalizingFirstLetter: String {
        prefix(1).uppercased() + dropFirst()
    }
}
