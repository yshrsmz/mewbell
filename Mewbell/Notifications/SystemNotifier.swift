import Foundation

/// `NotificationStore` が、新着の判定（`NotificationTracker`）の結果とアカウントの変化を伝える先。
@MainActor
protocol ThreadNotifying: AnyObject {
    /// アカウントの基準の取得を終えた。出ている通知のうち `threadIDs` に無いものを取り下げる。
    func baselineSet(for account: AccountID, keeping threadIDs: Set<String>)
    /// 基準の後の取得で、`posted` が新着になり、`retracted` が一覧から消えた。
    func threadsChanged(for account: AccountID, posted: [NotificationThread], retracted: Set<String>)
    /// スレッドを既読か Done にした。出ている通知を 1 回でまとめて取り下げる。
    func threadsRemoved(_ threadIDs: Set<String>, for account: AccountID)
    /// アカウントの出ている通知をすべて取り下げる（ポーリングを止めた、macOS の通知をオフにした）。
    func retractAll(for account: AccountID)
    /// `accounts` 以外のアカウントの通知をすべて取り下げる。
    func retainOnly(_ accounts: Set<AccountID>)
}

/// 新着の判定の結果から、macOS の通知を出し・取り下げる。
@MainActor
final class SystemNotifier: ThreadNotifying {
    private let center: any UserNotificationCenter
    /// アカウントの macOS の通知を出すか（設定）
    private let notifies: @MainActor (AccountID) -> Bool
    /// 通知に音を付けるか（設定）
    private let playsSound: @MainActor () -> Bool
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

    func baselineSet(for account: AccountID, keeping threadIDs: Set<String>) {
        removeStaleDelivered(for: account, keeping: threadIDs)
    }

    func threadsChanged(for account: AccountID, posted: [NotificationThread], retracted: Set<String>) {
        let sound = playsSound()
        let contents =
            notifies(account)
            ? posted.map { ThreadNotificationContent(thread: $0, account: account, playsSound: sound) } : []
        let identifiers = retracted.map { ThreadNotificationContent.identifier(threadID: $0, account: account) }
        enqueue { center in
            await center.removeDelivered(identifiers: identifiers)
            for content in contents {
                await center.add(content)
            }
        }
    }

    func threadsRemoved(_ threadIDs: Set<String>, for account: AccountID) {
        guard !threadIDs.isEmpty else { return }
        let identifiers = threadIDs.map { ThreadNotificationContent.identifier(threadID: $0, account: account) }
        enqueue { center in await center.removeDelivered(identifiers: identifiers) }
    }

    func retractAll(for account: AccountID) {
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
