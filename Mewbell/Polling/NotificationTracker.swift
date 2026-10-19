import Foundation

/// 取得の結果から、新着（初めて見たか `updated_at` が進んだスレッド）と、一覧から消えたスレッドを決める。
/// macOS の通知と一覧の自動展開の両方が使う。通知センターには触れない。
struct NotificationTracker {
    struct Changes: Equatable {
        /// 新着として知らせるスレッド
        var post: [NotificationThread] = []
        /// 一覧から消えたスレッドの ID
        var retract: Set<String> = []
    }

    /// アカウントごとの、見たスレッドと、最後に見たときの `updated_at`。一覧から消えたスレッドの分も残す
    /// （同じ `updated_at` のまま一覧に戻ったスレッドを、新着として知らせ直さないため）
    private var seen: [AccountID: [String: Date]] = [:]
    /// アカウントごとの今の一覧
    private var current: [AccountID: Set<String>] = [:]

    /// 基準の取得の結果を覚える。新着として知らせるものは無い。
    mutating func baseline(_ threads: [NotificationThread], for account: AccountID) {
        seen[account] = Dictionary(threads.map { ($0.id, $0.updatedAt) }, uniquingKeysWith: max)
        current[account] = Set(threads.map(\.id))
    }

    /// 基準の後の取得の結果から、新着と一覧から消えたものを決める。基準がまだ無ければ何も決めない
    /// （基準は呼び出し元が `hasBaseline` を見て `baseline` で覚える）。
    mutating func update(_ threads: [NotificationThread], for account: AccountID) -> Changes {
        guard var seenThreads = seen[account], let previous = current[account] else { return Changes() }
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

    /// 既読か Done にしたスレッドを今の一覧から外す（通知の取り下げは呼び出し元がする）。
    mutating func remove(_ threadIDs: Set<String>, for account: AccountID) {
        current[account]?.subtract(threadIDs)
    }

    /// アカウントの基準の取得を覚えているか。
    func hasBaseline(for account: AccountID) -> Bool {
        current[account] != nil
    }

    /// アカウントの記録を捨てる（止まった・消えたとき）。次の取得はまた基準になる。
    mutating func reset(_ account: AccountID) {
        seen[account] = nil
        current[account] = nil
    }
}
