import Foundation

/// 取得の結果から、どのスレッドの通知を出し、どれを取り下げるかを決める。通知センターには触れない。
struct NotificationTracker {
    struct Changes: Equatable {
        var post: [NotificationThread] = []
        /// 取り下げるスレッドの ID
        var retract: Set<String> = []
    }

    /// アカウントごとの、見たスレッドと、最後に見たときの `updated_at`。一覧から消えたスレッドの分も残す
    /// （同じ `updated_at` のまま一覧に戻ったスレッドを出し直さないため）
    private var seen: [AccountID: [String: Date]] = [:]
    /// アカウントごとの今の一覧
    private var current: [AccountID: Set<String>] = [:]

    /// 基準の取得の結果を覚える。何も出さない。
    mutating func baseline(_ threads: [NotificationThread], for account: AccountID) {
        seen[account] = Dictionary(threads.map { ($0.id, $0.updatedAt) }, uniquingKeysWith: max)
        current[account] = Set(threads.map(\.id))
    }

    /// 基準の後の取得の結果から、出すものと取り下げるものを決める。基準がまだ無ければ基準にする。
    mutating func update(_ threads: [NotificationThread], for account: AccountID) -> Changes {
        guard var seenThreads = seen[account], let previous = current[account] else {
            baseline(threads, for: account)
            return Changes()
        }
        var changes = Changes()
        for thread in threads {
            if let date = seenThreads[thread.id], date >= thread.updatedAt { continue }
            seenThreads[thread.id] = thread.updatedAt
            changes.post.append(thread)
        }
        let ids = Set(threads.map(\.id))
        changes.retract = previous.subtracting(ids)
        seen[account] = seenThreads
        current[account] = ids
        return changes
    }

    /// 既読にしたスレッドを今の一覧から外す（取り下げは呼び出し元がする）。
    mutating func remove(_ threadID: String, for account: AccountID) {
        current[account]?.remove(threadID)
    }

    /// アカウントの記録を捨てる（止まった・消えたとき）。次の取得はまた基準になる。
    mutating func reset(_ account: AccountID) {
        seen[account] = nil
        current[account] = nil
    }
}
