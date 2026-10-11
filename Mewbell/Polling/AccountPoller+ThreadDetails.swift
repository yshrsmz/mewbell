import Foundation

// スレッドの件名の状態とイベントの取得（polling「スレッドのイベントの取得」）。結果で取得の状態や失敗の記録は変えない
extension AccountPoller {
    /// 新着（前に知らせた一覧から増えたか `updated_at` が進んだスレッド）の状態とイベントを、一覧を知らせる前に取る。
    /// 最初の一覧と、スコープを確かめていないとき（トークンを取り直した直後）は取らない。
    func prefetchNewDetails(in threads: [NotificationThread], token: AccessToken) async {
        prefetchedIDs = []
        guard scopesVerified else { return }
        let targets = details.pending(in: threads, newOnly: true, limit: ThreadDetailsFetcher.prefetchLimit, now: now())
        guard !targets.isEmpty else { return }
        prefetchedIDs = Set(targets.map(\.id))
        let results = await ThreadDetailsFetcher(client: client, endpoints: endpoints)
            .fetch(targets, token: token, timeout: detailsTimeout)
        guard !Task.isCancelled else { return }
        details.record(results, now: now())
    }

    /// 一覧のスレッドのうち、まだ状態とイベントを取っていないものを取り、取れたものを付けて知らせ直す。取ったら true。
    /// 取っている間に一覧から外したスレッドは戻さない（今の一覧に付ける）。同じ回の知らせる前に取ったスレッドは、
    /// 失敗していても取り直さない（失敗の回数を 1 回の取得で 2 回数えないため）。
    /// `fillDetails` を、再読み込み（`refreshNow`）とループの停止で止められるように走らせる。取ったら true。
    func fillDetailsUnlessRefreshed() async -> Bool {
        let task = Task { await fillDetails() }
        fillTask = task
        defer { fillTask = nil }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func fillDetails() async -> Bool {
        defer { prefetchedIDs = [] }
        guard case .loaded = state.phase else { return false }
        let targets = details.pending(
            in: state.threads.filter { !prefetchedIDs.contains($0.id) }, newOnly: false,
            limit: ThreadDetailsFetcher.fillLimit, now: now())
        guard !targets.isEmpty, let token = await tokens.currentToken(for: accountID) else { return false }
        let results = await ThreadDetailsFetcher(client: client, endpoints: endpoints)
            .fetch(targets, token: token, timeout: detailsTimeout)
        guard !Task.isCancelled, !state.phase.isStopped else { return false }
        if details.record(results, now: now()) {
            state.threads = details.attach(to: state.threads)
            await publish(state)
        }
        return true
    }
}
