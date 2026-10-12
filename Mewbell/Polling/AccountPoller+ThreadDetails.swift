import Foundation

// スレッドの件名の状態とイベントの取得（polling「スレッドのイベントの取得」）。結果で取得の状態や失敗の記録は変えない
extension AccountPoller {
    /// 新着（前に知らせた一覧から増えたか `updated_at` が進んだスレッド）の状態とイベントを、一覧を知らせる前に取る。
    /// 最初の一覧と、スコープを確かめていないとき（トークンを取り直した直後）は取らない。再読み込みで止める。
    func prefetchNewDetails(in threads: [NotificationThread], token: AccessToken, fetchNumber: Int) async {
        guard scopesVerified else { return }
        let targets = details.pending(in: threads, newOnly: true, limit: ThreadDetailsFetcher.prefetchLimit, now: now())
        guard !targets.isEmpty else { return }
        let fetcher = ThreadDetailsFetcher(client: client, endpoints: endpoints)
        let timeout = detailsTimeout
        let results = await interruptibleByRefresh { await fetcher.fetch(targets, token: token, timeout: timeout) }
        guard let results, !Task.isCancelled else { return }
        // 取れた（結果を記録した）スレッドだけを、同じ回に取り直さないものとして覚える
        prefetched = (fetchNumber, Set(results.map(\.0.id)))
        details.record(results, now: now())
    }

    /// 一覧のスレッドのうち、まだ状態とイベントを取っていないものを取り、取れたものを付けて知らせ直す。取ったら true。
    /// 取っている間に一覧から外したスレッドは戻さない（今の一覧に付ける）。直前の取得の知らせる前に取ったスレッドは、
    /// 失敗していても取り直さない（失敗の回数を 1 回の取得で 2 回数えないため）。再読み込みで止める。
    func fillDetails() async -> Bool {
        guard case .loaded = state.phase else { return false }
        let skipped = prefetched.flatMap { $0.fetchNumber == fetchCount - 1 ? $0.ids : nil } ?? []
        let targets = details.pending(
            in: state.threads.filter { !skipped.contains($0.id) }, newOnly: false,
            limit: ThreadDetailsFetcher.fillLimit, now: now())
        guard !targets.isEmpty, let token = await tokens.currentToken(for: accountID) else { return false }
        let fetcher = ThreadDetailsFetcher(client: client, endpoints: endpoints)
        let timeout = detailsTimeout
        let results = await interruptibleByRefresh { await fetcher.fetch(targets, token: token, timeout: timeout) }
        guard let results, !Task.isCancelled, !state.phase.isStopped else { return false }
        if details.record(results, now: now()) {
            state.threads = details.attach(to: state.threads)
            await publish(state)
        }
        return true
    }

    /// `operation` を、再読み込み（`refreshNow` が `detailsTask` を止める）とループの停止で止められるように走らせる。
    /// 止められたら nil（途中までの結果は捨てる）。
    private func interruptibleByRefresh(
        _ operation: @escaping @Sendable () async -> ThreadDetailsFetcher.Results
    ) async -> ThreadDetailsFetcher.Results? {
        // 次の取得を待つ再読み込みがあるなら始めない（押したのが通知の取得の最中で、まだ止めるタスクが無かったとき）。
        // 再読み込みで始めた今の取得を待っている人は数えない（その取得の新着の分は取る）
        guard !refreshWaitsForNextFetch else { return nil }
        let task = Task { () -> ThreadDetailsFetcher.Results? in
            let results = await operation()
            return Task.isCancelled ? nil : results
        }
        detailsTask = task
        // 止めた古いループの後片付けで、新しいループの取得を消さないように、自分のものだけ消す
        defer { if detailsTask == task { detailsTask = nil } }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
