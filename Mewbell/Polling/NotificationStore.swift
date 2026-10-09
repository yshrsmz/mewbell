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

    /// `makePoller` が nil のときはポーリングしない（テストのホストや SwiftUI プレビュー用）。
    init(makePoller: PollerFactory?, feeds: [AccountID: FeedState] = [:]) {
        self.makePoller = makePoller
        self.feeds = feeds
    }

    static func live(tokens: any TokenProviding) -> NotificationStore {
        let client = GitHubAPIClient(transport: URLSessionTransport())
        return NotificationStore { account, endpoints, onUpdate in
            AccountPoller(
                accountID: account.id, endpoints: endpoints, client: client, tokens: tokens, onUpdate: onUpdate)
        }
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
        feeds[id] = state
    }
}
