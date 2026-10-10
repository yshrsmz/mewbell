import Foundation

/// `NotificationStore` が、通知の取得の状態の変化を伝える先。
@MainActor
protocol ThreadNotifying: AnyObject {
    /// アカウントの `FeedState` が `old` から `new` に変わった。
    func feedChanged(for account: AccountID, from old: FeedState?, to new: FeedState)
    /// スレッドを既読か Done にした。
    func threadRemoved(_ threadID: String, for account: AccountID)
    /// アカウントのポーリングを止めた（一覧から消えた、無効にした）。
    func accountRemoved(_ account: AccountID)
    /// アカウントの取得を最初からやり直す（「参加しているスレッドだけにする」を切り替えた）。次の取得を基準にする。
    func resetBaseline(_ account: AccountID)
    /// アカウントの macOS の通知をオフにした。出ている通知を取り下げる。
    func notificationsDisabled(_ account: AccountID)
    /// `accounts` 以外のアカウントの通知をすべて取り下げる。
    func retainOnly(_ accounts: Set<AccountID>)
}

/// 取得の状態の変化から、macOS の通知を出し・取り下げる。
@MainActor
final class SystemNotifier: ThreadNotifying {
    private let center: any UserNotificationCenter
    /// アカウントの macOS の通知を出すか（設定）
    private let notifies: @MainActor (AccountID) -> Bool
    /// 通知に音を付けるか（設定）
    private let playsSound: @MainActor () -> Bool
    private var tracker = NotificationTracker()
    /// 新着（通知の対象と同じ判定）が届いた。アカウントの通知の設定にかかわらず呼ぶ（一覧の折りたたみを開くため）
    var onNewThreads: (@MainActor (AccountID, [NotificationThread]) -> Void)?
    /// 通知センターへの操作を、呼んだ順に 1 つずつ流す（同じスレッドの追加と取り下げが入れ替わらないように）
    private var queue: Task<Void, Never>?

    init(
        center: any UserNotificationCenter, notifies: @escaping @MainActor (AccountID) -> Bool = { _ in true },
        playsSound: @escaping @MainActor () -> Bool = { true }
    ) {
        self.center = center
        self.notifies = notifies
        self.playsSound = playsSound
    }

    func feedChanged(for account: AccountID, from old: FeedState?, to new: FeedState) {
        switch new.phase {
        // 最初の取得が失敗を挟んで成功したとき（`.retrying` から `.loaded`）も、基準にする
        case .loaded where !tracker.hasBaseline(for: account):
            tracker.baseline(new.threads, for: account)
            removeStaleDelivered(for: account, keeping: Set(new.threads.map(\.id)))
        case .loaded:
            guard old?.threads != new.threads else { return }
            // 通知がオフでも見たスレッドは覚え続ける（オンに戻したときに、オフの間の分をまとめて通知しないため）
            let changes = tracker.update(new.threads, for: account)
            if !changes.post.isEmpty {
                onNewThreads?(account, changes.post)
            }
            let sound = playsSound()
            let posted = notifies(account) ? changes.post : []
            let contents = posted.map { ThreadNotificationContent(thread: $0, account: account, playsSound: sound) }
            let retracted = changes.retract.map { ThreadNotificationContent.identifier(threadID: $0, account: account) }
            enqueue { center in
                await center.removeDelivered(identifiers: retracted)
                for content in contents {
                    await center.add(content)
                }
            }
        case .scopeInsufficient, .unauthorized:
            accountRemoved(account)
        case .loading, .retrying:
            break
        }
    }

    func threadRemoved(_ threadID: String, for account: AccountID) {
        tracker.remove(threadID, for: account)
        let identifier = ThreadNotificationContent.identifier(threadID: threadID, account: account)
        enqueue { center in await center.removeDelivered(identifiers: [identifier]) }
    }

    func accountRemoved(_ account: AccountID) {
        tracker.reset(account)
        removeStaleDelivered(for: account, keeping: [])
    }

    func resetBaseline(_ account: AccountID) {
        // 出ている通知は、次の基準の取り直しで今の一覧に無いものだけを取り下げる
        tracker.reset(account)
    }

    func notificationsDisabled(_ account: AccountID) {
        // 見たスレッドは覚えたままにする（オンに戻したときに、オフの間に届いたものをまとめて通知しないため）
        removeStaleDelivered(for: account, keeping: [])
    }

    func retainOnly(_ accounts: Set<AccountID>) {
        let prefixes = accounts.map(ThreadNotificationContent.identifierPrefix(of:))
        removeDelivered { identifier in !prefixes.contains { identifier.hasPrefix($0) } }
    }

    /// 通知センターへの操作が終わるのを待つ（テスト用）。
    func waitForPendingWork() async {
        await queue?.value
    }

    /// アカウントの出ている通知のうち、`keeping` に無いスレッドのものを取り下げる。
    private func removeStaleDelivered(for account: AccountID, keeping threadIDs: Set<String>) {
        let prefix = ThreadNotificationContent.identifierPrefix(of: account)
        removeDelivered { identifier in
            identifier.hasPrefix(prefix) && !threadIDs.contains(String(identifier.dropFirst(prefix.count)))
        }
    }

    /// 出ている通知のうち、`isStale` に当てはまるものを取り下げる。
    private func removeDelivered(where isStale: @escaping @Sendable (String) -> Bool) {
        enqueue { center in
            await center.removeDelivered(identifiers: center.deliveredIdentifiers().filter(isStale))
        }
    }

    private func enqueue(_ operation: @escaping @Sendable (any UserNotificationCenter) async -> Void) {
        let previous = queue
        let center = center
        queue = Task {
            await previous?.value
            await operation(center)
        }
    }
}
