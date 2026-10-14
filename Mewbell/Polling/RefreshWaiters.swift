import Foundation

/// 再読み込みで早めた取得を待っている人と、早めてよい時刻を持つ（`AccountPoller` の中だけで使う）。
struct RefreshWaiters {
    /// 再読み込みで早めた取得を、前の取得を始めてからこれより早くはしない（連打で叩きすぎないため）
    static let minimumInterval: TimeInterval = 10

    /// 取得を試みた回数（トークンが無くて送らなかった回も数える）
    private var attempts = 0
    private var lastAttemptStartedAt: Date?
    /// `attempt` 回目の試みが終わったら起こす
    private var waiters: [(attempt: Int, continuation: CheckedContinuation<Void, Never>)] = []

    /// `lastAttemptStartedAt` は、作り直す前のポーラーが取得を始めた時刻（試みの数には数えない）。
    init(lastAttemptStartedAt: Date? = nil) {
        self.lastAttemptStartedAt = lastAttemptStartedAt
    }

    var isEmpty: Bool { waiters.isEmpty }
    /// 今の試みより後の試みを待っている人がいるか（今の試みの途中で再読み込みが押された）
    var waitsForLaterAttempt: Bool { waiters.contains { $0.attempt > attempts } }

    mutating func startAttempt(at date: Date) {
        attempts += 1
        lastAttemptStartedAt = date
    }

    /// 次に始める試みが終わるまで待たせる（取得の途中なら、その次の試み）。
    mutating func add(_ continuation: CheckedContinuation<Void, Never>) {
        waiters.append((attempts + 1, continuation))
    }

    /// 終わった試みまでを待っている人を起こす。`all` ならすべて（ループが終わったとき）。
    mutating func finish(all: Bool = false) {
        let split = waiters.partition { all || $0.attempt <= attempts }
        let finished = waiters[split...]
        waiters.removeSubrange(split...)
        for waiter in finished {
            waiter.continuation.resume()
        }
    }

    /// 前の試みを始めてから `minimumInterval` までの残り。たっていれば nil。
    /// 時計が戻ったとき（差が負）も、`minimumInterval` より長くは待たない。
    func remainingWait(now: Date) -> Duration? {
        let elapsed = lastAttemptStartedAt.map { now.timeIntervalSince($0) } ?? Self.minimumInterval
        let remaining = min(Self.minimumInterval - elapsed, Self.minimumInterval)
        return remaining > 0 ? .seconds(remaining) : nil
    }
}
