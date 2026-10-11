import Foundation

/// 1 アカウントの、スレッドの件名の状態とイベントの記録（polling「スレッドのイベントの取得」）。メモリにだけ持つ。
/// `AccountPoller` の中で使う。
struct ThreadDetailsCache {
    private struct Entry {
        let updatedAt: Date
        /// 「無い」だったときは nil（その `updated_at` の間は取り直さない）
        let details: ThreadDetails?
    }

    private var entries: [String: Entry] = [:]
    /// 前に知らせた一覧のスレッドの `updated_at`（新着の判定に使う）。最初の一覧の前は nil
    private var previous: [String: Date]?
    /// レート制限が解ける時刻。それまでは取らない
    private var pausedUntil: Date?

    /// ID と `updated_at` が一致する記録を付けたスレッド（一致しなければ外す）。
    func attach(to threads: [NotificationThread]) -> [NotificationThread] {
        threads.map { thread in
            var thread = thread
            thread.details = entries[thread.id].flatMap { $0.updatedAt == thread.updatedAt ? $0.details : nil }
            return thread
        }
    }

    /// 取得を待っているスレッドを、更新日時の新しい順に `limit` 件まで。`newOnly` なら前に知らせた一覧から増えたか
    /// `updated_at` が進んだものだけ（前に知らせた一覧が無ければ空）。レート制限で止めている間は空。
    func pending(in threads: [NotificationThread], newOnly: Bool, limit: Int, now: Date) -> [NotificationThread] {
        if let pausedUntil, now < pausedUntil { return [] }
        if newOnly && previous == nil { return [] }
        return
            threads
            .filter { thread in
                guard thread.subjectNumber != nil, entries[thread.id]?.updatedAt != thread.updatedAt else {
                    return false
                }
                guard newOnly, let previous else { return true }
                return previous[thread.id].map { $0 < thread.updatedAt } ?? true
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { $0 }
    }

    /// 取得の結果をまとめて記録する。1 つでも記録したら true（一覧に付け直す必要がある）。
    @discardableResult
    mutating func record(_ results: [(NotificationThread, ThreadDetailsFetchResult)]) -> Bool {
        results.map { record($0.1, for: $0.0) }.contains(true)
    }

    /// 取得の結果を記録する。記録したら true。
    @discardableResult
    mutating func record(_ result: ThreadDetailsFetchResult, for thread: NotificationThread) -> Bool {
        switch result {
        case .found(let details):
            entries[thread.id] = Entry(updatedAt: thread.updatedAt, details: details)
            return true
        case .unavailable:
            entries[thread.id] = Entry(updatedAt: thread.updatedAt, details: nil)
            return true
        case .rateLimited(let retryAt):
            pausedUntil = max(pausedUntil ?? retryAt, retryAt)
            return false
        case .unauthorized, .failed:
            return false
        }
    }

    /// 一覧を知らせた。新着の判定の基準にし、一覧に無いスレッドの記録を捨てる。
    mutating func listed(_ threads: [NotificationThread]) {
        previous = Dictionary(threads.map { ($0.id, $0.updatedAt) }, uniquingKeysWith: max)
        entries = entries.filter { previous?[$0.key] != nil }
    }

    /// すべて捨てる（アカウントが止まったとき）。次の一覧は最初の一覧として扱う。
    mutating func reset() {
        self = ThreadDetailsCache()
    }
}
