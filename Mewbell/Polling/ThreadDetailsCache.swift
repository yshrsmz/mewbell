import Foundation

/// 1 アカウントの、スレッドの件名の状態とイベントの記録（polling「スレッドのイベントの取得」）。メモリにだけ持つ。
/// `AccountPoller` の中で使う。
struct ThreadDetailsCache {
    private struct Entry {
        let updatedAt: Date
        /// 「無い」だったときは nil（その `updated_at` の間は取り直さない）
        let details: ThreadDetails?
    }

    /// 同じ `updated_at` で一時的な失敗が続いたら、取り直すのをやめる回数
    static let failureLimit = 3

    private var entries: [String: Entry] = [:]
    /// 一時的な失敗・認証の失敗が続いた回数（`updated_at` ごと）
    private var failures: [String: (updatedAt: Date, count: Int)] = [:]
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
        let waiting = threads.filter { thread in
            guard thread.subjectNumber != nil || thread.releaseID != nil,
                entries[thread.id]?.updatedAt != thread.updatedAt
            else {
                return false
            }
            guard newOnly, let previous else { return true }
            return previous[thread.id].map { $0 < thread.updatedAt } ?? true
        }
        return Array(waiting.sorted { $0.updatedAt > $1.updatedAt }.prefix(limit))
    }

    /// レート制限で止める最短の時間（429 に待ち時間のヘッダーが無いときに、すぐ取り直さないため）
    static let minimumPause: TimeInterval = 60

    /// 取得の結果をまとめて記録する。1 つでも記録したら true（一覧に付け直す必要がある）。
    @discardableResult
    mutating func record(_ results: ThreadDetailsFetcher.Results, now: Date) -> Bool {
        results.map { thread, result in
            guard case .rateLimited(let retryAt) = result else { return record(result, for: thread) }
            return record(.rateLimited(retryAt: max(retryAt, now + Self.minimumPause)), for: thread)
        }.contains(true)
    }

    /// 取得の結果を記録する。記録したら true。
    @discardableResult
    mutating func record(_ result: ThreadDetailsFetchResult, for thread: NotificationThread) -> Bool {
        switch result {
        case .found(let details):
            failures[thread.id] = nil
            entries[thread.id] = Entry(updatedAt: thread.updatedAt, details: details)
            return true
        case .unavailable:
            failures[thread.id] = nil
            entries[thread.id] = Entry(updatedAt: thread.updatedAt, details: nil)
            return true
        case .rateLimited(let retryAt):
            pausedUntil = max(pausedUntil ?? retryAt, retryAt)
            return false
        case .unauthorized, .failed:
            // 移したリポジトリのリダイレクトなど、続けて失敗するスレッドを取り直し続けないように、回数で打ち切る
            let previous = failures[thread.id].flatMap { $0.updatedAt == thread.updatedAt ? $0.count : nil } ?? 0
            guard previous + 1 >= Self.failureLimit else {
                failures[thread.id] = (thread.updatedAt, previous + 1)
                return false
            }
            failures[thread.id] = nil
            entries[thread.id] = Entry(updatedAt: thread.updatedAt, details: nil)
            return true
        }
    }

    /// 一覧を知らせた。新着の判定の基準にし、一覧に無いスレッドの記録を捨てる。
    mutating func listed(_ threads: [NotificationThread]) {
        previous = Dictionary(threads.map { ($0.id, $0.updatedAt) }, uniquingKeysWith: max)
        entries = entries.filter { previous?[$0.key] != nil }
        failures = failures.filter { previous?[$0.key] != nil }
    }

    /// すべて捨てる（アカウントが止まったとき）。次の一覧は最初の一覧として扱う。
    mutating func reset() {
        self = ThreadDetailsCache()
    }
}
