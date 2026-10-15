import Foundation
import Observation
import os

/// アカウントごとの通知の取得の状態を UI に見せ、アカウントの状態に合わせてポーラーを起動・停止する。
@MainActor
@Observable
final class NotificationStore {
    /// ポーラーを作る。`participating` は「参加しているスレッドだけにする」の設定。`initialPhase` は作り直す前の止まった状態、
    /// `carriedWait` は作り直す前の取得の待ち。
    /// 作り直す前の止まった状態かレート制限の待ちを持ち越す。`onUpdate` はポーラーの状態が変わるたびに呼ばれる。
    typealias PollerFactory =
        @MainActor (
            _ account: Account, _ endpoints: APIEndpoints, _ participating: Bool, _ initialPhase: FeedPhase?,
            _ carriedWait: CarriedWait?,
            _ onUpdate: @escaping @Sendable (FeedState) async -> Void
        )
        -> AccountPoller

    private(set) var feeds: [AccountID: FeedState] = [:] {
        didSet { updateRepositories(from: oldValue) }
    }
    /// アカウントごとのリポジトリのグループ。一覧だけが使う並べ方なので、ポーラーではなくここで、スレッドが変わったときに
    /// 1 回だけ作る。描画の中ではグループ分けをしない。
    private(set) var repositories: [AccountID: [RepositoryGroup]] = [:]
    /// 再読み込みで早めた取得が終わっていない
    private(set) var isRefreshing = false

    @ObservationIgnored private static let logger = Logger(category: "Polling")
    @ObservationIgnored private let makePoller: PollerFactory?
    @ObservationIgnored private var pollers: [AccountID: PollerEntry] = [:]
    @ObservationIgnored private var nextGeneration = 0
    /// 新着の判定と、macOS の通知・`onNewThreads` への受け渡し
    @ObservationIgnored private let threadChanges: ThreadChangeDispatcher
    @ObservationIgnored private let openURL: @MainActor (URL) -> Void
    /// アカウントごとの設定（ポーラーを作るときの `participating`）
    @ObservationIgnored private let preferences: @MainActor (AccountID) -> AccountPreferences
    /// ポーラーがまだ無いアカウントで、既読にするスレッド（起動の直後に通知をクリックされたとき）
    @ObservationIgnored private var pendingReads: [AccountID: Set<String>] = [:]
    /// 止めたポーラーの、次の取得を早めてよい時刻（無効にしてすぐ有効に戻したときに間隔やレート制限の待ちを抜けないように）
    @ObservationIgnored private var carriedWaits: [AccountID: CarriedWait] = [:]
    /// 読み込みが終わって、残すアカウント（一覧にあって無効でない）が決まった（一覧の折りたたみの状態を整理するため）
    @ObservationIgnored private let onAccountsRetained: (@MainActor (Set<AccountID>) -> Void)?

    /// `makePoller` が nil のときはポーリングしない（テストのホストや SwiftUI プレビュー用）。
    /// `openURL` は既定値を持たせない（テストで本物のブラウザを開かないように、呼び出し元に必ず渡させる）。
    init(
        makePoller: PollerFactory?, notifier: (any ThreadNotifying)? = nil,
        openURL: @escaping @MainActor (URL) -> Void,
        preferences: @escaping @MainActor (AccountID) -> AccountPreferences = { _ in .default },
        onNewThreads: (@MainActor (AccountID, [NotificationThread]) -> Void)? = nil,
        onAccountsRetained: (@MainActor (Set<AccountID>) -> Void)? = nil,
        feeds: [AccountID: FeedState] = [:]
    ) {
        self.makePoller = makePoller
        threadChanges = ThreadChangeDispatcher(notifier: notifier, onNewThreads: onNewThreads)
        self.openURL = openURL
        self.preferences = preferences
        self.onAccountsRetained = onAccountsRetained
        self.feeds = feeds
        // didSet は init では呼ばれないので、ここでも作る
        updateRepositories(from: [:])
    }

    /// `oldValue` からスレッドが変わったアカウントだけ作り直し、`feeds` から消えたアカウントを消す。
    private func updateRepositories(from oldValue: [AccountID: FeedState]) {
        for id in oldValue.keys where feeds[id] == nil {
            repositories[id] = nil
        }
        for (id, feed) in feeds where oldValue[id]?.threads != feed.threads {
            repositories[id] = RepositoryGroup.groups(from: feed.threads)
        }
    }

    // init（規則の対象外）の引数を中継するだけの組み立て関数なので、引数の数の上限を外す
    // swiftlint:disable:next function_parameter_count
    static func live(
        tokens: any TokenProviding, notifier: any ThreadNotifying,
        preferences: @escaping @MainActor (AccountID) -> AccountPreferences,
        openURL: @escaping @MainActor (URL) -> Void,
        onNewThreads: @escaping @MainActor (AccountID, [NotificationThread]) -> Void,
        onAccountsRetained: @escaping @MainActor (Set<AccountID>) -> Void
    ) -> NotificationStore {
        let client = GitHubAPIClient(transport: URLSessionTransport())
        return NotificationStore(
            makePoller: { account, endpoints, participating, initialPhase, carriedWait, onUpdate in
                AccountPoller(
                    accountID: account.id, endpoints: endpoints, client: client, tokens: tokens,
                    participating: participating, initialPhase: initialPhase, carriedWait: carriedWait,
                    onUpdate: onUpdate)
            }, notifier: notifier, openURL: openURL,
            preferences: preferences, onNewThreads: onNewThreads,
            onAccountsRetained: onAccountsRetained)
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
        let active = state.enabledStatuses
        let keptIDs = Set(active.map(\.id))
        for id in pollers.keys where !keptIDs.contains(id) {
            let entry = pollers.removeValue(forKey: id)
            entry?.poller.stop()
            carriedWaits[id] = carriedWait(of: id, startedWith: entry?.carriedWait)
            feeds[id] = nil
            threadChanges.accountRemoved(id)
        }
        if let retained = state.retainedAccountIDs {
            threadChanges.retainOnly(retained)
            // 読み込みが終わっても一覧に無いか、トークンを取れない・無効のアカウントの既読化は捨てる
            let waitingIDs = Set(active.filter { $0.tokenState != .unavailable }.map(\.id))
            pendingReads = pendingReads.filter { waitingIDs.contains($0.key) }
            onAccountsRetained?(retained)
        }
        for account in active.filter({ $0.tokenState == .ready }).map(\.account) where pollers[account.id] == nil {
            startPolling(account)
        }
    }

    /// 「参加しているスレッドだけにする」を切り替えたとき。ポーラーを止めて一覧を捨て、新しい設定で最初の取得から
    /// 始め直す（前の `Last-Modified` や隠しているスレッドは別の一覧のものなので持ち越さない）。トークンは捨てない。
    /// 「スコープ不足」「認証エラー」で止まっているアカウントは、止まったまま作り直す（再開は再読み込みのときだけ）。
    /// それ以外は、取得の待ちを持ち越す（`CarriedWait`）。
    func restart(_ id: AccountID) {
        guard let entry = pollers.removeValue(forKey: id) else { return }
        entry.poller.stop()
        let initialPhase = feeds[id].flatMap { $0.phase.isStopped ? $0.phase : nil }
        carriedWaits[id] = carriedWait(of: id, startedWith: entry.carriedWait)
        feeds[id] = nil
        threadChanges.restarted(id)
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
        let carriedWait = carriedWaits.removeValue(forKey: id).flatMap { $0.until > Date() ? $0 : nil }
        let poller = makePoller(account, endpoints, preferences(id).participatingOnly, initialPhase, carriedWait) {
            [weak self] state in
            await self?.apply(state, for: id, generation: generation)
        }
        pollers[id] = PollerEntry(poller: poller, generation: generation, account: account, carriedWait: carriedWait)
        if let initialPhase {
            feeds[id] = FeedState(phase: initialPhase, threads: [])
            return
        }
        feeds[id] = carriedWait?.initialPhase.map { FeedState(phase: $0, threads: []) } ?? .loading
        Self.logger.info("Started polling \(id)")
        for threadID in pendingReads.removeValue(forKey: id) ?? [] {
            Task { await poller.perform(.read(threadID: threadID)) }
        }
        poller.start()
    }

    /// 止めるポーラーの代わりに作るポーラーに持ち越す待ち。止めるポーラー自身が持ち越した待ちをまだ待っている
    /// （最初の取得をしていない）なら、その待ちも残す（作り直しを重ねて待ちが縮まないように）。
    private func carriedWait(of id: AccountID, startedWith previous: CarriedWait?) -> CarriedWait? {
        let current = feeds[id].flatMap { CarriedWait(from: $0, now: Date()) }
        guard let previous, previous.until > Date(), feeds[id]?.threads.isEmpty != false,
            feeds[id]?.phase == .loading || feeds[id]?.phase.isRateLimited == true
        else { return current }
        return previous.merged(with: current)
    }

    /// 再読み込み: 全アカウントを次の予定を待たずに `If-Modified-Since` なしで取得し、「スコープ不足」「認証エラー」で
    /// 止まっているアカウントは再開する。押したときのアカウントの取得がすべて終わるまで `isRefreshing` を立てる。
    func refresh() {
        guard !isRefreshing else { return }
        for (id, _) in pollers where feeds[id]?.phase.isStopped == true {
            // Diagnostics の値（最後の失敗など）は、再開したポーラーが出し直すまで残す
            feeds[id] = FeedState(
                phase: .loading, threads: [], diagnostics: feeds[id]?.diagnostics ?? FeedDiagnostics())
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

    /// アカウントのホストの Web の通知一覧をブラウザで開く。既読にはしない。URL を組み立てられなければ開かない。
    func openWebNotifications(for account: AccountID) {
        guard let endpoints = APIEndpoints(host: account.host),
            let url = ThreadWebURL.notificationsPage(endpoints: endpoints)
        else { return }
        openURL(url)
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
        threadChanges.threadRemoved(threadID, for: account)
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
        threadChanges.stopAll()
    }

    private func apply(_ state: FeedState, for id: AccountID, generation: Int) {
        // 止めたポーラーから遅れて届いた更新は捨てる
        guard pollers[id]?.generation == generation, feeds[id] != state else { return }
        let old = feeds[id]
        feeds[id] = state
        threadChanges.feedChanged(for: id, from: old, to: state)
    }
}

/// 動いているポーラーと、その世代（止めたポーラーから遅れて届いた更新を捨てるため）、作ったときのアカウント。
private struct PollerEntry {
    let poller: AccountPoller
    let generation: Int
    let account: Account
    /// 作ったときに持ち越した待ち
    let carriedWait: CarriedWait?
}
