import AppKit
import Foundation
import Observation
import os

/// アカウントごとの通知の取得の状態を UI に見せ、アカウントの状態に合わせてポーラーを起動・停止する。
@MainActor
@Observable
final class NotificationStore {
    /// ポーラーを作る。`participating` は「参加しているスレッドだけにする」の設定。`initialPhase` があれば、
    /// 作り直す前の止まった状態かレート制限の待ちを持ち越す。`onUpdate` はポーラーの状態が変わるたびに呼ばれる。
    typealias PollerFactory =
        @MainActor (
            _ account: Account, _ endpoints: APIEndpoints, _ participating: Bool, _ initialPhase: FeedPhase?,
            _ firstFetchNotBefore: Date?,
            _ onUpdate: @escaping @Sendable (FeedState) async -> Void
        )
        -> AccountPoller

    private(set) var feeds: [AccountID: FeedState] = [:]
    /// 再読み込みで早めた取得が終わっていない
    private(set) var isRefreshing = false

    @ObservationIgnored private static let logger = Logger(category: "Polling")
    @ObservationIgnored private let makePoller: PollerFactory?
    @ObservationIgnored private var pollers: [AccountID: PollerEntry] = [:]
    @ObservationIgnored private var nextGeneration = 0
    @ObservationIgnored private let notifier: (any ThreadNotifying)?
    @ObservationIgnored private let openURL: @MainActor (URL) -> Void
    /// アカウントごとの設定（ポーラーを作るときの `participating`）
    @ObservationIgnored private let preferences: @MainActor (AccountID) -> AccountPreferences
    /// ポーラーがまだ無いアカウントで、既読にするスレッド（起動の直後に通知をクリックされたとき）
    @ObservationIgnored private var pendingReads: [AccountID: Set<String>] = [:]
    /// 止めたポーラーの、次の取得を早めてよい時刻（無効にしてすぐ有効に戻したときに間隔やレート制限の待ちを抜けないように）
    @ObservationIgnored private var notBefore: [AccountID: Date] = [:]

    /// `makePoller` が nil のときはポーリングしない（テストのホストや SwiftUI プレビュー用）。
    /// `openURL` は既定値を持たせない（テストで本物のブラウザを開かないように、呼び出し元に必ず渡させる）。
    init(
        makePoller: PollerFactory?, notifier: (any ThreadNotifying)? = nil,
        openURL: @escaping @MainActor (URL) -> Void,
        preferences: @escaping @MainActor (AccountID) -> AccountPreferences = { _ in .default },
        feeds: [AccountID: FeedState] = [:]
    ) {
        self.makePoller = makePoller
        self.notifier = notifier
        self.openURL = openURL
        self.preferences = preferences
        self.feeds = feeds
    }

    static func live(tokens: any TokenProviding, notifier: any ThreadNotifying, settings: AppSettings)
        -> NotificationStore
    {
        let client = GitHubAPIClient(transport: URLSessionTransport())
        return NotificationStore(
            makePoller: { account, endpoints, participating, initialPhase, firstFetchNotBefore, onUpdate in
                AccountPoller(
                    accountID: account.id, endpoints: endpoints, client: client, tokens: tokens,
                    participating: participating, initialPhase: initialPhase, firstFetchNotBefore: firstFetchNotBefore,
                    onUpdate: onUpdate)
            }, notifier: notifier, openURL: { NSWorkspace.shared.open($0) },
            preferences: { settings.preferences(for: $0) })
    }

    /// 全アカウントの未読の一覧の件数の合計（止まったアカウントと無効のアカウントはスレッドを持たないので 0 件）。
    var unreadCount: Int {
        feeds.values.reduce(0) { $0 + $1.threads.count }
    }

    /// トークンが「使える」アカウントのポーラーを起動し、一覧から消えたアカウントと無効にしたアカウントの
    /// ポーラーを止めて状態を消す（全体の状態が「アカウントあり」以外になったら、すべて止める）。すでにポーラーが
    /// あるアカウントは、トークンの取得中や「トークンを取れない」の間もそのままにする
    /// （作り直すと、止めたポーリングが勝手に再開したり、取り直しと重なったりするため）。
    func sync(with state: DiscoveryState) {
        guard makePoller != nil else { return }
        let statuses: [AccountStatus] = if case .accounts(let statuses) = state { statuses } else { [] }
        let active = statuses.filter { $0.tokenState != .disabled }
        let keptIDs = Set(active.map(\.id))
        for id in pollers.keys where !keptIDs.contains(id) {
            pollers.removeValue(forKey: id)?.poller.stop()
            notBefore[id] = feeds[id].flatMap(Self.nextFetchNotBefore)
            feeds[id] = nil
            notifier?.accountRemoved(id)
        }
        if state != .checking {
            notifier?.retainOnly(keptIDs)
            // 読み込みが終わっても一覧に無いか、トークンを取れない・無効のアカウントの既読化は捨てる
            let waitingIDs = Set(active.filter { $0.tokenState != .unavailable }.map(\.id))
            pendingReads = pendingReads.filter { waitingIDs.contains($0.key) }
        }
        for account in statuses.filter({ $0.tokenState == .ready }).map(\.account) where pollers[account.id] == nil {
            startPolling(account)
        }
    }

    /// 「参加しているスレッドだけにする」を切り替えたとき。ポーラーを止めて一覧を捨て、新しい設定で最初の取得から
    /// 始め直す（前の `Last-Modified` や隠しているスレッドは別の一覧のものなので持ち越さない）。トークンは捨てない。
    /// 「スコープ不足」「認証エラー」で止まっているアカウントは、止まったまま作り直す（再開は再読み込みのときだけ）。
    /// レート制限で待っているアカウントは、前の再試行の時刻まで最初の取得を待つ（制限を早めない）。
    func restart(_ id: AccountID) {
        guard let entry = pollers.removeValue(forKey: id) else { return }
        entry.poller.stop()
        let initialPhase = feeds[id].flatMap { $0.phase.isStopped || $0.phase.isRateLimited ? $0.phase : nil }
        notBefore[id] = feeds[id].flatMap(Self.nextFetchNotBefore)
        feeds[id] = nil
        notifier?.resetBaseline(id)
        startPolling(entry.account, initialPhase: initialPhase)
    }

    private func startPolling(_ account: Account, initialPhase: FeedPhase? = nil) {
        guard let makePoller else { return }
        guard let endpoints = APIEndpoints(host: account.host) else {
            Self.logger.error("Could not derive the API endpoints of \(account.id)")
            return
        }
        let generation = nextGeneration
        nextGeneration += 1
        let id = account.id
        let firstFetchNotBefore = notBefore.removeValue(forKey: id).flatMap { $0 > Date() ? $0 : nil }
        let poller = makePoller(
            account, endpoints, preferences(id).participatingOnly, initialPhase, firstFetchNotBefore
        ) { [weak self] state in
            await self?.apply(state, for: id, generation: generation)
        }
        pollers[id] = PollerEntry(poller: poller, generation: generation, account: account)
        if let initialPhase {
            feeds[id] = FeedState(phase: initialPhase, threads: [])
            guard initialPhase.isRateLimited else { return }
        } else {
            feeds[id] = .loading
        }
        Self.logger.info("Started polling \(id)")
        for threadID in pendingReads.removeValue(forKey: id) ?? [] {
            Task { await poller.perform(.read(threadID: threadID)) }
        }
        poller.start()
    }

    /// 止めたポーラーの代わりに作るポーラーの最初の取得を、早めてよい時刻。レート制限で待っていればその再試行の時刻、
    /// 取得できていれば最後の取得から再読み込みと同じ下限（`RefreshWaiters.minimumInterval`）がたった時刻。
    private static func nextFetchNotBefore(_ feed: FeedState) -> Date? {
        switch feed.phase {
        case .retrying(let nextAttempt, rateLimited: true): nextAttempt
        case .loaded(let updatedAt): updatedAt.addingTimeInterval(RefreshWaiters.minimumInterval)
        case .loading, .retrying, .scopeInsufficient, .unauthorized: nil
        }
    }

    /// 再読み込み: 全アカウントを次の予定を待たずに `If-Modified-Since` なしで取得し、「スコープ不足」「認証エラー」で
    /// 止まっているアカウントは再開する。押したときのアカウントの取得がすべて終わるまで `isRefreshing` を立てる。
    func refresh() {
        guard !isRefreshing else { return }
        for (id, _) in pollers where feeds[id]?.phase.isStopped == true {
            feeds[id] = .loading
        }
        let targets = pollers.values.map(\.poller)
        isRefreshing = true
        Task {
            await withTaskGroup(of: Void.self) { group in
                for poller in targets {
                    group.addTask { await poller.refreshNow() }
                }
            }
            isRefreshing = false
        }
    }

    /// 一覧のスレッドをブラウザで開いて既読にする。URL を組み立てられなければ、開かず既読にもしない。
    func open(_ thread: NotificationThread, in account: AccountID) {
        guard let endpoints = APIEndpoints(host: account.host),
            let url = ThreadWebURL.make(for: thread, endpoints: endpoints)
        else { return }
        openURL(url)
        perform(.read(threadID: thread.id), in: account)
    }

    /// macOS の通知のクリックから、検証済みの URL を開いて既読にする。
    func openFromNotification(_ request: ThreadOpenRequest) {
        openURL(request.url)
        perform(.read(threadID: request.threadID), in: request.account)
    }

    /// 一覧のスレッドを、開かずに既読にする。
    func markRead(_ thread: NotificationThread, in account: AccountID) {
        perform(.read(threadID: thread.id), in: account)
    }

    /// 一覧のスレッドを Done にする。
    func markDone(_ thread: NotificationThread, in account: AccountID) {
        perform(.done(threadID: thread.id), in: account)
    }

    /// アカウントの一覧を、表示している一覧の最新のスレッドまですべて既読にする。一覧から外すのはポーラーで、
    /// その結果は `apply` で届く（取得できていない・トークンが無いときに外さない判断を、ポーラーの 1 か所でするため）。
    func markAllRead(in account: AccountID) {
        guard let feed = feeds[account], feed.canMarkAllRead, let newest = feed.newestUpdate,
            let poller = pollers[account]?.poller
        else { return }
        Task { await poller.markAllRead(through: newest) }
    }

    /// 一覧からすぐに外し、ポーラーに操作を頼む。既読はポーラーがまだ無ければ、作るときまで取っておく
    /// （起動の直後に通知をクリックされたとき）。Done はポーラーが無ければ何もしない（一覧の行はポーラーがあるときだけ出る）。
    private func perform(_ action: ThreadAction, in account: AccountID) {
        let poller = pollers[account]?.poller
        if poller == nil, case .done = action { return }
        let threadID = action.threadID
        feeds[account]?.threads.removeAll { $0.id == threadID }
        notifier?.threadRemoved(threadID, for: account)
        if let poller {
            Task { await poller.perform(action) }
        } else {
            pendingReads[account, default: []].insert(threadID)
        }
    }

    /// すべてのポーラーを止めて状態を消す（終了時）。
    func stopAll() {
        for entry in pollers.values {
            entry.poller.stop()
        }
        pollers.removeAll()
        feeds.removeAll()
    }

    private func apply(_ state: FeedState, for id: AccountID, generation: Int) {
        // 止めたポーラーから遅れて届いた更新は捨てる
        guard pollers[id]?.generation == generation, feeds[id] != state else { return }
        let old = feeds[id]
        feeds[id] = state
        notifier?.feedChanged(for: id, from: old, to: state)
    }
}

/// 動いているポーラーと、その世代（止めたポーラーから遅れて届いた更新を捨てるため）、作ったときのアカウント。
private struct PollerEntry {
    let poller: AccountPoller
    let generation: Int
    let account: Account
}
