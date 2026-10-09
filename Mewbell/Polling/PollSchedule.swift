import Foundation

/// 取得の結果から、次の取得までの待ち時間を決める。
enum PollSchedule {
    /// `X-Poll-Interval` が無いときの間隔で、これより短くは問い合わせない
    static let minimumInterval = 60
    /// 失敗が続いたときの待ち時間の上限
    static let maximumBackoff = 900

    /// 成功（200 / 304）の後: `X-Poll-Interval` と 60 秒の大きいほう。
    static func afterSuccess(pollInterval: Int?) -> Duration {
        .seconds(max(minimumInterval, pollInterval ?? minimumInterval))
    }

    /// レート制限の後に待つ上限（GitHub のレート制限は 1 時間で戻る。壊れた `X-RateLimit-Reset` で止まり続けないように）
    static let maximumRateLimitWait = 3600

    /// レート制限の後: `retryAt` まで。60 秒より短ければ 60 秒、1 時間より長ければ 1 時間。
    static func afterRateLimit(retryAt: Date, now: Date) -> Duration {
        let seconds = retryAt.timeIntervalSince(now)
        let clamped =
            seconds.isFinite
            ? min(max(seconds.rounded(.up), Double(minimumInterval)), Double(maximumRateLimitWait))
            : Double(maximumRateLimitWait)
        return .seconds(Int(clamped))
    }

    /// そのほかの失敗の後: 60 秒から失敗が続くたびに 2 倍にし、15 分を上限にする。
    static func afterFailure(consecutiveFailures: Int) -> Duration {
        let exponent = min(max(consecutiveFailures - 1, 0), 10)
        return .seconds(min(minimumInterval << exponent, maximumBackoff))
    }
}

/// 1 回の取得の後にすること。
enum PollStep {
    /// 待ってから次の取得をする
    case wait(Duration)
    /// トークンを取り直したので、すぐに取得をやり直す
    case retryNow
    /// 止まった
    case stop
}
