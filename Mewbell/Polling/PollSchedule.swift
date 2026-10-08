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

    /// レート制限の後: `retryAt` まで。60 秒より短ければ 60 秒。
    static func afterRateLimit(retryAt: Date, now: Date) -> Duration {
        let seconds = retryAt.timeIntervalSince(now)
        return .seconds(max(Double(minimumInterval), seconds.isFinite ? seconds.rounded(.up) : 0))
    }

    /// そのほかの失敗の後: 60 秒から失敗が続くたびに 2 倍にし、15 分を上限にする。
    static func afterFailure(consecutiveFailures: Int) -> Duration {
        let exponent = min(max(consecutiveFailures - 1, 0), 10)
        return .seconds(min(minimumInterval << exponent, maximumBackoff))
    }
}
