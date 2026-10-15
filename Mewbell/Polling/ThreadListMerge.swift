import Foundation

/// 条件付きの取得（`If-Modified-Since` を付けた取得）の `200` を、今の一覧に重ねる。GitHub はその `200` に、
/// その時刻より後に `updated_at` が進んだスレッドだけを入れるので、受け取らなかったスレッドは一覧に残す。
enum ThreadListMerge {
    /// `fetched` を受け取った順に並べ、その後に `current` のうち `fetched` と ID が重ならないものを `current` の順に並べる。
    static func merge(_ fetched: [NotificationThread], into current: [NotificationThread]) -> [NotificationThread] {
        let fetchedIDs = Set(fetched.map(\.id))
        return fetched + current.filter { !fetchedIDs.contains($0.id) }
    }
}
