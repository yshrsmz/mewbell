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
