import Foundation

/// アカウントの通知の取得の状態。
enum FeedPhase: Sendable, Equatable {
    /// 最初の取得中（再開の直後を含む）
    case loading
    /// 取得できた
    case loaded(updatedAt: Date)
    /// 失敗して `nextAttempt` まで待っている（スレッドは最後に取得できたもの）
    case retrying(nextAttempt: Date, rateLimited: Bool)
    /// トークンに `repo` も `notifications` も無いので止めた
    case scopeInsufficient
    /// トークンを取り直しても 401 だったので止めた
    case unauthorized

    /// 再読み込みを押すまで取得しない状態か。
    /// レート制限で待っている
    var isRateLimited: Bool {
        if case .retrying(_, rateLimited: true) = self { true } else { false }
    }

    var isStopped: Bool {
        switch self {
        case .scopeInsufficient, .unauthorized: true
        case .loading, .loaded, .retrying: false
        }
    }
}

struct FeedState: Sendable, Equatable {
    var phase: FeedPhase
    var threads: [NotificationThread]

    static let loading = FeedState(phase: .loading, threads: [])

    /// 一覧のスレッドの `updated_at` の最大値（すべて既読の範囲）。
    var newestUpdate: Date? {
        threads.map(\.updatedAt).max()
    }

    /// 「すべて既読」を押せるか（取得できていて、一覧が 1 件以上あるとき）。
    var canMarkAllRead: Bool {
        guard case .loaded = phase else { return false }
        return !threads.isEmpty
    }
}
