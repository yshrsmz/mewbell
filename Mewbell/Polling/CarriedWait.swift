import Foundation

/// 作り直すポーラーに持ち越す取得の待ち（「参加しているスレッドだけにする」の切り替えや、無効にしてすぐ有効に戻したとき）。
struct CarriedWait: Sendable, Equatable {
    /// 最初の取得をこの時刻まで待つ
    var until: Date
    /// レート制限の待ち（再読み込みでも早めない）
    var rateLimited: Bool
    /// 前の取得を始めた時刻。再読み込みで早めるときも、ここから `RefreshWaiters.minimumInterval` は空ける
    var lastAttemptStartedAt: Date?

    /// 止めるポーラーの状態から決める。失敗やレート制限で待っていればその再試行の時刻、取得できていれば最後の取得から、
    /// 取得中なら今から、再読み込みと同じ下限（10 秒）がたった時刻まで待つ。止まっていれば持ち越さない（再開は再読み込みで）。
    init?(from feed: FeedState, now: Date) {
        let interval = RefreshWaiters.minimumInterval
        switch feed.phase {
        case .retrying(let nextAttempt, let rateLimited):
            // 失敗した取得の時刻は持っていないので、最も遅い場合（最短の待ちの 60 秒前）とみなす
            self.init(
                until: nextAttempt, rateLimited: rateLimited,
                lastAttemptStartedAt: rateLimited
                    ? nil : nextAttempt.addingTimeInterval(-Double(PollSchedule.minimumInterval)))
        case .loaded(let updatedAt):
            self.init(
                until: updatedAt.addingTimeInterval(interval), rateLimited: false, lastAttemptStartedAt: updatedAt)
        case .loading:
            self.init(until: now.addingTimeInterval(interval), rateLimited: false, lastAttemptStartedAt: now)
        case .scopeInsufficient, .unauthorized:
            return nil
        }
    }

    init(until: Date, rateLimited: Bool, lastAttemptStartedAt: Date?) {
        self.until = until
        self.rateLimited = rateLimited
        self.lastAttemptStartedAt = lastAttemptStartedAt
    }

    /// 作り直したポーラーの最初の状態。レート制限の待ちは表示も持ち越す（再読み込みでも早めないように）。
    var initialPhase: FeedPhase? {
        rateLimited ? .retrying(nextAttempt: until, rateLimited: true) : nil
    }

    /// 2 つの待ちの、どちらも守る待ち（遅い時刻まで待ち、どちらかがレート制限ならレート制限として扱う）。
    func merged(with other: CarriedWait?) -> CarriedWait {
        guard let other else { return self }
        let last = [lastAttemptStartedAt, other.lastAttemptStartedAt].compactMap { $0 }.max()
        return CarriedWait(
            until: max(until, other.until), rateLimited: rateLimited || other.rateLimited, lastAttemptStartedAt: last)
    }
}
