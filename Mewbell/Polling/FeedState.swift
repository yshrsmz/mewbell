import Foundation

/// アカウントの通知の取得の状態。
enum FeedPhase: Sendable, Equatable {
    /// 最初の取得中（再開の直後を含む）
    case loading
    /// 取得できた
    case loaded(updatedAt: Date)
    /// 失敗して `nextAttempt` まで待っている（スレッドは最後に取得できたもの）
    case retrying(nextAttempt: Date, rateLimited: Bool, lastSuccess: Date?)
    /// トークンに `repo` も `notifications` も無いので止めた
    case scopeInsufficient
    /// トークンを取り直しても 401 だったので止めた
    case unauthorized

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

    static let loading = FeedState(phase: .loading, threads: [])
}
