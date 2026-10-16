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

    /// レート制限で待っている
    var isRateLimited: Bool {
        if case .retrying(_, rateLimited: true) = self { true } else { false }
    }

    /// `delay` 後に取り直す「失敗して待っている」。
    static func retrying(after delay: Duration, rateLimited: Bool, now: Date) -> FeedPhase {
        .retrying(nextAttempt: now.adding(delay), rateLimited: rateLimited)
    }

    /// 一覧を出す状態か（取得できた、失敗して待っている）。
    var showsThreads: Bool {
        switch self {
        case .loaded, .retrying: true
        case .loading, .scopeInsufficient, .unauthorized: false
        }
    }

    /// 再読み込みを押すまで取得しない状態か。
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
    /// 最後に取得し終えた一覧が、10 ページで打ち切ったものか
    var isTruncated = false
    /// ポップオーバーで知らせる操作の失敗（その後に送った取得が成功したら消す）
    var actionFailure: ActionFailure?
    /// Diagnostics に出す値
    var diagnostics = FeedDiagnostics()

    static let loading = FeedState(phase: .loading, threads: [])

    /// 一覧のスレッドの `updated_at` の最大値（すべて既読の範囲）。
    var newestUpdate: Date? {
        threads.map(\.updatedAt).max()
    }

    /// 「すべて既読」と「すべて Done」を押せるか（取得できていて、一覧が 1 件以上あるとき）。
    var canMarkAll: Bool {
        guard case .loaded = phase else { return false }
        return !threads.isEmpty
    }
}
