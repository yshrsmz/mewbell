import Foundation
import Synchronization
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

    /// スレッドを既読か Done にする。一覧からすぐに外し、リクエストを送り、次の取得を条件なしにする。
    /// 止まっているときとトークンが無いときは送らない（次の条件なしの取得で、未読のままなら一覧に戻る）。
    func perform(_ action: ThreadAction) async {
        let threadID = action.threadID
        HiddenThreads.beginRequest(for: threadID, in: &hidden)
        if state.threads.contains(where: { $0.id == threadID }) {
            state.threads.removeAll { $0.id == threadID }
            await publish(state)
        }
        // 止まっているかはトークンを待った後に見る。止まっていれば送らず、失敗も記録しない（取得の状態で伝わる）
        let token = await tokens.currentToken(for: accountID)
        var failure: FailureKind?
        if !state.phase.isStopped {
            failure =
                if let token { FailureKind(await client.perform(action, endpoints: endpoints, token: token)) } else {
                    .noToken
                }
        }
        // 結果が 304 に隠れないように、また失敗したスレッドが一覧に戻るように、次は条件なしで取り直す
        // （失敗を知らせる前に済ませる。知らせている間に始まった取得で、スレッドが戻らないまま知らせが消えないように）
        HiddenThreads.endRequest(for: threadID, fetchCount: fetchCount, in: &hidden)
        unconditionalRequested.store(true, ordering: .relaxed)
        if let failure { await recordActionFailure(ThreadActionKind(action), failure) }
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
        unconditionalRequested.store(true, ordering: .relaxed)
        if let failure = FailureKind(result) {
            await recordActionFailure(.markAllRead, failure)
        }
    }
}
