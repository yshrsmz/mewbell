import AppKit
import Foundation
import Observation
import os

/// アカウントごとの通知の取得の状態を UI に見せ、アカウントの状態に合わせてポーラーを起動・停止する。
@MainActor
@Observable
final class NotificationStore {
    /// ポーラーを作る。`onUpdate` はポーラーの状態が変わるたびに呼ばれる。
    typealias PollerFactory =
        @MainActor (
            _ account: Account, _ endpoints: APIEndpoints, _ onUpdate: @escaping @Sendable (FeedState) async -> Void
        )
        -> AccountPoller

    private(set) var feeds: [AccountID: FeedState] = [:]

    @ObservationIgnored private static let logger = Logger(category: "Polling")
    @ObservationIgnored private let makePoller: PollerFactory?
    @ObservationIgnored private var pollers: [AccountID: (poller: AccountPoller, generation: Int)] = [:]
    @ObservationIgnored private var nextGeneration = 0
    @ObservationIgnored private let notifier: (any ThreadNotifying)?
    @ObservationIgnored private let openURL: @MainActor (URL) -> Void
    /// ポーラーがまだ無いアカウントで、既読にするスレッド（起動の直後に通知をクリックされたとき）
    @ObservationIgnored private var pendingReads: [AccountID: Set<String>] = [:]

    /// `makePoller` が nil のときはポーリングしない（テストのホストや SwiftUI プレビュー用）。
    init(
        makePoller: PollerFactory?, notifier: (any ThreadNotifying)? = nil,
        openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) },
        feeds: [AccountID: FeedState] = [:]
    ) {
        self.makePoller = makePoller
        self.notifier = notifier
        self.openURL = openURL
        self.feeds = feeds
    }

    static func live(tokens: any TokenProviding, notifier: any ThreadNotifying) -> NotificationStore {
        let client = GitHubAPIClient(transport: URLSessionTransport())
        return NotificationStore(
            makePoller: { account, endpoints, onUpdate in
                AccountPoller(
                    accountID: account.id, endpoints: endpoints, client: client, tokens: tokens, onUpdate: onUpdate)
            }, notifier: notifier)
    }

    /// 全アカウントの未読の一覧の件数の合計（止まったアカウントはスレッドを持たないので 0 件）。
    var unreadCount: Int {
        feeds.values.reduce(0) { $0 + $1.threads.count }
    }

    /// トークンが「使える」アカウントのポーラーを起動し、一覧から消えたアカウントのポーラーを止めて状態を消す
    /// （全体の状態が「アカウントあり」以外になったら、すべて止める）。すでにポーラーがあるアカウントは、
    /// トークンの取得中や「トークンを取れない」の間もそのままにする
    /// （作り直すと、止めたポーリングが勝手に再開したり、取り直しと重なったりするため）。
    func sync(with state: DiscoveryState) {
        guard let makePoller else { return }
        let statuses: [AccountStatus] = if case .accounts(let statuses) = state { statuses } else { [] }
        let keptIDs = Set(statuses.map(\.id))
        for id in pollers.keys where !keptIDs.contains(id) {
            pollers.removeValue(forKey: id)?.poller.stop()
            feeds[id] = nil
            notifier?.accountRemoved(id)
        }
        if state != .checking {
            notifier?.retainOnly(keptIDs)
            // 読み込みが終わっても一覧に無いか、トークンを取れないアカウントの既読化は捨てる
            let waitingIDs = Set(statuses.filter { $0.tokenState != .unavailable }.map(\.id))
            pendingReads = pendingReads.filter { waitingIDs.contains($0.key) }
        }
        for account in statuses.filter({ $0.tokenState == .ready }).map(\.account) where pollers[account.id] == nil {
            guard let endpoints = APIEndpoints(host: account.host) else {
                Self.logger.error("Could not derive the API endpoints of \(account.id)")
                continue
            }
            let generation = nextGeneration
            nextGeneration += 1
            let id = account.id
            let poller = makePoller(account, endpoints) { [weak self] state in
                await self?.apply(state, for: id, generation: generation)
            }
            pollers[id] = (poller, generation)
            feeds[id] = .loading
            Self.logger.info("Started polling \(id)")
            for threadID in pendingReads.removeValue(forKey: id) ?? [] {
                Task { await poller.perform(.read(threadID: threadID)) }
            }
            poller.start()
        }
    }

    /// 「スコープ不足」「認証エラー」で止まっているアカウントのポーリングを再開する（再読み込みボタン）。
    func resumeStopped() {
        for (id, entry) in pollers where feeds[id]?.phase.isStopped == true {
            feeds[id] = .loading
            entry.poller.resume()
        }
    }

    /// 止まっていないアカウントの次の取得を `If-Modified-Since` なしにする（再読み込みボタン）。取得は早めない。
    /// 止まっているアカウントは、再開でトークンを取り直すので、どのみち条件なしになる。
    func requestUnconditionalFetch() {
        for (id, entry) in pollers where feeds[id]?.phase.isStopped != true {
            entry.poller.requestUnconditionalFetch()
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

    /// アカウントの「すべて既読」を押せるか（取得できていて、一覧が 1 件以上あるとき）。
    func canMarkAllRead(_ account: AccountID) -> Bool {
        feeds[account]?.canMarkAllRead ?? false
    }

    /// アカウントの一覧をすべて既読にする。一覧から外すのはポーラーで、その結果は `apply` で届く
    /// （止まっている・トークンが無いときに外さない判断を、ポーラーの 1 か所でするため）。
    func markAllRead(in account: AccountID) {
        guard canMarkAllRead(account), let poller = pollers[account]?.poller else { return }
        Task { await poller.markAllRead() }
    }

    /// 一覧からすぐに外し、ポーラーに操作を頼む。既読はポーラーがまだ無ければ、作るときまで取っておく
    /// （起動の直後に通知をクリックされたとき）。
    private func perform(_ action: ThreadAction, in account: AccountID) {
        let threadID = action.threadID
        feeds[account]?.threads.removeAll { $0.id == threadID }
        notifier?.threadRemoved(threadID, for: account)
        if let poller = pollers[account]?.poller {
            Task { await poller.perform(action) }
        } else if case .read = action {
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
