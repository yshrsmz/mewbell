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
    var threads: [NotificationThread] {
        didSet { repositories = RepositoryGroup.groups(from: threads) }
    }
    /// `threads` をリポジトリごとにまとめたもの。スレッドが変わったときに 1 回だけ作り、描画のたびには作らない
    /// （`threads` から決まるので、Equatable の比較の結果は変わらない）。
    private(set) var repositories: [RepositoryGroup]
    /// 最後に取得し終えた一覧が、10 ページで打ち切ったものか
    var isTruncated: Bool
    /// ポップオーバーで知らせる操作の失敗（その後に送った取得が成功したら消す）
    var actionFailure: ActionFailure?
    /// Diagnostics に出す値
    var diagnostics: FeedDiagnostics

    /// didSet は init では呼ばれないので、ここでも `repositories` を作る。
    init(
        phase: FeedPhase, threads: [NotificationThread], isTruncated: Bool = false, actionFailure: ActionFailure? = nil,
        diagnostics: FeedDiagnostics = FeedDiagnostics()
    ) {
        self.phase = phase
        self.threads = threads
        self.repositories = RepositoryGroup.groups(from: threads)
        self.isTruncated = isTruncated
        self.actionFailure = actionFailure
        self.diagnostics = diagnostics
    }

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
