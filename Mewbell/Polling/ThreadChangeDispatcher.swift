import Foundation

/// 新着の判定（`NotificationTracker`）を更新し、その結果を macOS の通知（`ThreadNotifying`）と `onNewThreads` に知らせる。
/// 出来事ごとに、判定の操作と通知の取り下げのどちらを（または両方を）行うかを、この型の中で決める
/// （`NotificationStore` が判定と通知を別々に呼んで、組み合わせを取り違えないように）。
@MainActor
final class ThreadChangeDispatcher {
    /// 新着の判定（macOS の通知と一覧の自動展開で共有する）。通知の設定にかかわらず更新する
    /// （通知をオフにしている間に見たスレッドを、オンに戻したときにまとめて通知しないため）
    private var tracker = NotificationTracker()
    private let notifier: (any ThreadNotifying)?
    /// 新着（macOS の通知の対象と同じ判定）が届いた。アカウントの通知の設定にかかわらず呼ぶ（一覧の折りたたみを開くため）
    private let onNewThreads: (@MainActor (AccountID, [NotificationThread]) -> Void)?

    init(
        notifier: (any ThreadNotifying)?, onNewThreads: (@MainActor (AccountID, [NotificationThread]) -> Void)?
    ) {
        self.notifier = notifier
        self.onNewThreads = onNewThreads
    }

    /// 取得の状態の変化から新着と消えたスレッドを判定し、macOS の通知と `onNewThreads` に知らせる。
    func feedChanged(for id: AccountID, from old: FeedState?, to new: FeedState) {
        switch new.phase {
        // 最初の取得が失敗を挟んで成功したとき（`.retrying` から `.loaded`）も、基準にする
        case .loaded where !tracker.hasBaseline(for: id):
            tracker.baseline(new.threads, for: id)
            notifier?.baselineSet(for: id, keeping: Set(new.threads.map(\.id)))
        case .loaded:
            guard old?.threads != new.threads else { return }
            let changes = tracker.update(new.threads, for: id)
            if !changes.post.isEmpty {
                onNewThreads?(id, changes.post)
            }
            if !changes.post.isEmpty || !changes.retract.isEmpty {
                notifier?.threadsChanged(for: id, posted: changes.post, retracted: changes.retract)
            }
        case .scopeInsufficient, .unauthorized:
            accountRemoved(id)
        case .loading, .retrying:
            break
        }
    }

    /// スレッドを既読か Done にした。今の一覧から外し、出ている通知をまとめて取り下げる。
    func threadsRemoved(_ threadIDs: Set<String>, for account: AccountID) {
        tracker.remove(threadIDs, for: account)
        notifier?.threadsRemoved(threadIDs, for: account)
    }

    /// アカウントのポーリングを止めた（一覧から消えた、無効にした、止まった）。記録を捨て、出ている通知を取り下げる。
    func accountRemoved(_ account: AccountID) {
        tracker.reset(account)
        notifier?.retractAll(for: account)
    }

    /// アカウントのポーラーを作り直した。次の取得を基準にする。
    /// 判定だけを捨てる: 出ている通知は、次の最初の成功した取得（基準）で今の一覧に無いものだけを取り下げて整理するので、
    /// ここでは取り下げない。
    func restarted(_ account: AccountID) {
        tracker.reset(account)
    }

    /// `accounts` 以外のアカウントの通知をすべて取り下げる。
    /// 通知だけを取り下げる: 消えたアカウントの判定は、その前に `accountRemoved` で（ポーラーを止めたときに）捨てている。
    /// ポーラーを作っていなかったアカウントには、捨てる判定が無い。
    func retainOnly(_ accounts: Set<AccountID>) {
        notifier?.retainOnly(accounts)
    }

    /// すべてのポーラーを止めた。すべてのアカウントの記録を捨てる（次に作るポーラーの最初の取得は基準になる）。
    /// 判定だけを捨てる: 終了のときだけ呼ばれ、出ている通知は取り下げずに通知センターに残す（終了した後もクリックで
    /// 開けるように）。残った通知は、次に起動したときの最初の成功した取得（基準）で、一覧に無いものを取り下げる。
    func stopAll() {
        tracker = NotificationTracker()
    }
}
