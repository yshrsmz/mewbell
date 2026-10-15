import Foundation
import os

// 一覧のスレッドへの操作と、操作したスレッドを取得の結果から隠す処理
extension AccountPoller {
    /// 操作の失敗をログに書き、記録して UI に知らせる。
    private func recordActionFailure(_ action: ThreadActionKind, _ kind: FailureKind) async {
        Self.logger.error(
            "Could not apply \(String(describing: action)) to \(self.accountID): \(String(describing: kind))")
        recorder.recordActionFailure(action, kind, at: now(), fetchCount: fetchCount, in: &state)
        await publish(state)
    }

    /// スレッドを既読か Done にする。どれも一覧からすぐに外し、配列の順に 1 件ずつリクエストを送り、次の取得を条件なしにする。
    /// 認証エラーかレート制限になったら残りは送らない。止まっているとき・`stop()` の後・トークンが無いときは送らない
    /// （送らなかったスレッドは、次の条件なしの取得で未読のままなら一覧に戻る）。失敗は最後の 1 つだけを知らせる。
    func perform(_ actions: [ThreadAction]) async {
        guard !actions.isEmpty else { return }
        for action in actions {
            HiddenThreads.beginRequest(for: action.threadID, in: &hidden)
        }
        let threadIDs = Set(actions.map(\.threadID))
        if state.threads.contains(where: { threadIDs.contains($0.id) }) {
            state.threads.removeAll { threadIDs.contains($0.id) }
            await publish(state)
        }
        var failure: (action: ThreadAction, kind: FailureKind)?
        var sending = true
        // 二次レート制限を避けるため、並行させずに 1 件ずつ送る
        for action in actions {
            if sending {
                // 1 件ごとにトークンを読み直し、止まっていないかを確かめ直す（送っている間に止まったり、無効化・削除・終了で
                // トークンを捨てたりしたら、手元のトークンで残りを送らない）。止まっているかはトークンを待った後に見る。
                // 止まっていれば送らず、それまでの失敗も記録しない（取得の状態で伝わる）
                let token = await tokens.currentToken(for: accountID)
                if state.phase.isStopped || isDiscarded {
                    sending = false
                    failure = nil
                } else if let kind = await send(action, token: token) {
                    failure = (action, kind)
                    // トークンが無い・認証エラー・レート制限なら、残りも同じ理由で失敗するので送らない
                    sending = kind != .noToken && kind != .unauthorized && kind != .rateLimited
                }
            }
            // 結果が 304 に隠れないように、また失敗したスレッドや送らなかったスレッドが一覧に戻るように、次は条件なしで取り直す
            // （取得を始めるときに読んで消すので、残りを送っている間に始まる取得にも効くよう、1 件ごとに立てる）。
            // 失敗を知らせる前に済ませる（知らせている間に始まった取得で、スレッドが戻らないまま知らせが消えないように）
            HiddenThreads.endRequest(for: action.threadID, fetchCount: fetchCount, in: &hidden)
            unconditionalRequested = true
        }
        if let failure { await recordActionFailure(ThreadActionKind(failure.action), failure.kind) }
    }

    /// 操作のリクエストを送り、失敗の種類を返す。成功なら nil。トークンが無ければ送らずに `noToken`。
    private func send(_ action: ThreadAction, token: AccessToken?) async -> FailureKind? {
        guard let token else { return .noToken }
        return FailureKind(await markThread(action, token: token))
    }

    /// 操作に応じて、`GitHubAPIClient` の既読か Done のメソッドを呼ぶ。
    private func markThread(_ action: ThreadAction, token: AccessToken) async -> ThreadActionResult {
        switch action {
        case .read(let threadID): await client.markThreadRead(endpoints: endpoints, token: token, threadID: threadID)
        case .done(let threadID): await client.markThreadDone(endpoints: endpoints, token: token, threadID: threadID)
        }
    }

    /// `newest`（ユーザーが押したときに表示していた一覧の `updated_at` の最大値）までを、すべて既読にする。
    /// 一覧からすぐに外し、`PUT /notifications` を送り、次の取得を条件なしにする。取得できていないとき、
    /// 一覧が空のときは何もしない。トークンが無いときは送らずに失敗として知らせる。押した後に届いたスレッドは外さない。
    func markAllRead(through newest: Date) async {
        // 取得の状態は、トークンを待っている間に変わることがあるので待った後に見る
        let token = await tokens.currentToken(for: accountID)
        guard case .loaded = state.phase, !state.threads.isEmpty else {
            Self.logger.info("Skipped marking all threads of \(self.accountID) as read: no loaded list")
            return
        }
        guard let token else {
            await recordActionFailure(.markAllRead, .noToken)
            return
        }
        // `last_read_at` は秒までしか送らないので、隠す範囲も秒に揃える
        let cutoff = Date(timeIntervalSince1970: newest.timeIntervalSince1970.rounded(.down))
        let serial = readThroughCount
        readThroughCount += 1
        readThroughs[serial] = ReadThrough(cutoff: cutoff, until: .requestInFlight)
        state.threads.removeAll { $0.updatedAt <= cutoff }
        await publish(state)

        let result = await client.markAllRead(endpoints: endpoints, token: token, lastReadAt: cutoff)
        // 止まって消されていたら、戻さない
        readThroughs[serial]?.finish(
            succeeded: result == .succeeded, fetchCount: fetchCount, at: now(), holdFor: Self.unconditionalFetchInterval
        )
        unconditionalRequested = true
        if let failure = FailureKind(result) {
            await recordActionFailure(.markAllRead, failure)
        }
    }
}
