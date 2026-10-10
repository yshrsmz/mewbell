import Foundation

/// 既読にしたスレッドを、いつまで取得の結果から取り除くか。
enum HiddenUntil {
    /// 終わっていない既読化のリクエストがある（数を持つのは、同じスレッドを続けて既読にしたとき、先に終わった分で隠すのをやめないため）
    case requestsInFlight(Int)
    /// この番号以降の取得の 200 が出るまで（既読化の後に始めた取得なら、結果をそのまま信じてよい）
    case fetch(Int)
}

/// すべて既読にした範囲（`updated_at` が `cutoff` 以前のスレッド）を、どの取得の結果から取り除くか。
struct ReadThrough {
    let cutoff: Date
    var until: Until

    enum Until {
        /// リクエストの結果が出るまで、どの取得の結果からも取り除く
        case requestInFlight
        /// 成功した: 結果が出る前に始めた取得と、結果から `deadline` までに始めた取得の結果から取り除く
        /// （`202` で GitHub が既読にし終えるまでの分。時計が `completedAt` より前に戻ったら、もう取り除かない）
        case succeeded(fetchesBefore: Int, completedAt: Date, deadline: Date)
        /// 失敗した: この番号より前に始めた取得の結果からだけ取り除く
        case failed(fetchesBefore: Int)
    }

    /// リクエストの結果が出た。`fetchCount` は次に始める取得の番号、`holdFor` は成功したときに取り除き続ける時間。
    mutating func finish(succeeded: Bool, fetchCount: Int, at completedAt: Date, holdFor: TimeInterval) {
        until =
            succeeded
            ? .succeeded(
                fetchesBefore: fetchCount, completedAt: completedAt, deadline: completedAt.addingTimeInterval(holdFor))
            : .failed(fetchesBefore: fetchCount)
    }

    /// この番号・開始時刻の取得の結果から取り除くか。取得は順に行うので、一度 false になったらその後も false。
    func applies(toFetch number: Int, startedAt: Date) -> Bool {
        switch until {
        case .requestInFlight:
            true
        case .succeeded(let fetchesBefore, let completedAt, let deadline):
            number < fetchesBefore || (completedAt <= startedAt && startedAt < deadline)
        case .failed(let fetchesBefore):
            number < fetchesBefore
        }
    }
}

/// 操作したスレッドを取得の結果から隠す処理。
enum HiddenThreads {
    /// スレッドへの操作のリクエストを始める（終わるまで、どの取得の結果からも隠す）。
    static func beginRequest(for threadID: String, in hidden: inout [String: HiddenUntil]) {
        if case .requestsInFlight(let count) = hidden[threadID] {
            hidden[threadID] = .requestsInFlight(count + 1)
        } else {
            hidden[threadID] = .requestsInFlight(1)
        }
    }

    /// スレッドへの操作のリクエストが終わった。ほかに終わっていないリクエストが無ければ、`fetchCount`（次に始める取得の番号）
    /// 以降の取得の 200 が出るまで隠す。
    static func endRequest(for threadID: String, fetchCount: Int, in hidden: inout [String: HiddenUntil]) {
        if case .requestsInFlight(let count) = hidden[threadID], count > 1 {
            hidden[threadID] = .requestsInFlight(count - 1)
        } else {
            hidden[threadID] = .fetch(fetchCount)
        }
    }

    /// 操作の後に始めた取得の結果なら隠すのをやめ、そうでなければ既読・Done・すべて既読にしたスレッドを取り除く。
    /// 取得は 1 つのループで順に行うので、番号と開始時刻は結果の届く順に増える。
    static func revealOrHide(
        _ threads: [NotificationThread], hidden: inout [String: HiddenUntil], readThroughs: inout [Int: ReadThrough],
        fetchNumber: Int, startedAt: Date
    ) -> [NotificationThread] {
        hidden = hidden.filter { _, until in
            guard case .fetch(let first) = until else { return true }
            return fetchNumber < first
        }
        readThroughs = readThroughs.filter { _, readThrough in
            readThrough.applies(toFetch: fetchNumber, startedAt: startedAt)
        }
        let cutoff = readThroughs.values.map(\.cutoff).max()
        return threads.filter { thread in
            hidden[thread.id] == nil && (cutoff.map { thread.updatedAt > $0 } ?? true)
        }
    }
}
