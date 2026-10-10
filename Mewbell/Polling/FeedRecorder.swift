import Foundation

/// 取得と操作の結果から、`FeedState` の打ち切り・Diagnostics の値・知らせる操作の失敗を書き換える
/// （`AccountPoller` の中で、取得の番号と一緒に使う）。
struct FeedRecorder {
    /// 知らせる操作の失敗を、この番号以降の取得の成功で消す
    private var noticeClearsFromFetch: Int?

    /// 取得の結果を記録する。失敗なら最後の取得の失敗にし、成功なら 200 の打ち切りとスコープを入れ、
    /// 操作の失敗の後に送った取得なら知らせる失敗を消す（失敗したスレッドはその取得で一覧に戻っている）。
    mutating func recordFetch(
        _ result: NotificationsFetchResult, number: Int, at date: Date, in state: inout FeedState
    ) {
        // スコープ不足の 403 でも、受け取ったスコープを出す（何が足りないかを見られるように）
        if case .forbidden(let scopes) = result, scopes.scopes != nil {
            state.diagnostics.scopes = scopes
        }
        if let kind = FailureKind(result) {
            state.diagnostics.lastFetchFailure = TimedFailure(kind: kind, occurredAt: date)
            return
        }
        if case .updated(_, _, _, let scopes, let truncated) = result {
            state.diagnostics.scopes = scopes
            state.isTruncated = truncated
        }
        if let clearsFrom = noticeClearsFromFetch, number >= clearsFrom {
            state.actionFailure = nil
            noticeClearsFromFetch = nil
        }
    }

    /// 操作の失敗を、知らせる失敗と最後の操作の失敗の両方に記録する。`fetchCount` は次に始める取得の番号。
    /// リクエストの間に止まっていたら、知らせる失敗は記録しない（止まっていることは取得の状態で伝わる）。
    mutating func recordActionFailure(
        _ action: ThreadActionKind, _ kind: FailureKind, at date: Date, fetchCount: Int, in state: inout FeedState
    ) {
        let failure = ActionFailure(action: action, kind: kind, occurredAt: date)
        state.diagnostics.lastActionFailure = failure
        guard !state.phase.isStopped else { return }
        state.actionFailure = failure
        noticeClearsFromFetch = fetchCount
    }

    /// 止まった状態（再開してトークンを取り直している間の `.loading` を含む）。スレッド、打ち切り、知らせる失敗、
    /// 次の取得の予定は捨て、そのほかの Diagnostics の値は持ち越す。
    mutating func stopped(as phase: FeedPhase, from state: FeedState) -> FeedState {
        noticeClearsFromFetch = nil
        var diagnostics = state.diagnostics
        diagnostics.nextFetchAt = nil
        return FeedState(phase: phase, threads: [], diagnostics: diagnostics)
    }
}
