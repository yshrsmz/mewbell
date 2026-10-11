import Foundation
import Synchronization
import os

/// 1 アカウントの通知をポーリングする。ループは 1 つだけ走らせる。
/// スレッドへの操作（`AccountPoller+ThreadActions.swift`）と状態とイベントの取得（`AccountPoller+ThreadDetails.swift`）が使う
/// プロパティは、別のファイルから見えるように private にしていない
/// （actor に閉じているので、外からは書き換えられない）。
actor AccountPoller {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    static let logger = Logger(category: "Polling")
    /// 条件なしの取得の間隔。`Last-Modified` は未読の `updated_at` の最新値なので、それより古いスレッドの増減は
    /// `304` に隠れる。その分のずれを、この間隔で取り直して直す
    static let unconditionalFetchInterval: TimeInterval = 300

    let accountID: AccountID
    let endpoints: APIEndpoints
    let client: GitHubAPIClient
    let tokens: any TokenProviding
    private let participating: Bool  // `participating=true` で取得する（切り替えたらポーラーを作り直す）
    private let firstFetchNotBefore: Date?  // 最初の取得をこの時刻まで待つ（`CarriedWait.until`）
    let detailsTimeout: Duration  // 1 回にまとめて状態とイベントを取るのにかける時間の上限
    private let sleep: Sleep
    let now: @Sendable () -> Date
    private let onUpdate: @Sendable (FeedState) async -> Void

    /// 走っているループ。actor に入らずに起動・停止できるように、ロックで持つ
    /// `discarded` は `stop()` で立て、その後は起動も再開もしない（取り除いたアカウントのトークンで取得し続けないため）
    private nonisolated let loop = Mutex<(task: Task<Void, Never>?, discarded: Bool)>((nil, false))
    /// 次の取得を条件なしにする印（再読み込み）。actor に入らずに立てられるように、アトミックに持つ
    nonisolated let unconditionalRequested = Atomic(false)

    var state = FeedState.loading
    /// 最後にすべてのページを取り終えた 200 の `Last-Modified`
    private var lastModified: String?
    /// 最後に 200 で全ページを取り終えた時刻（`If-Modified-Since` を付けた取得でも 200 なら一覧はすべて取り直される）
    private var lastFullFetch: Date?
    /// 今のトークンでスコープを確かめたか
    var scopesVerified = false
    private var consecutiveFailures = 0
    /// 始めた取得の数（次に始める取得の番号）
    var fetchCount = 0
    /// 既読・Done にしたので、取得の結果から取り除いているスレッド
    var hidden: [String: HiddenUntil] = [:]
    /// すべて既読にしたので、取得の結果から `updated_at` で取り除いている範囲（すべて既読の番号ごと）
    var readThroughs: [Int: ReadThrough] = [:]
    /// 次のすべて既読に振る番号
    var readThroughCount = 0
    /// スレッドの件名の状態とイベント
    var details = ThreadDetailsCache()
    /// この回の、一覧を知らせる前に状態とイベントを取ったスレッド
    var prefetched: (fetchNumber: Int, ids: Set<String>)?
    /// 打ち切り・Diagnostics の値・知らせる操作の失敗の記録
    var recorder = FeedRecorder()
    /// 走っているループの番号（止めたループが後から終わったときに、新しいループの状態を消さないため）
    private var runningLoop: Int?
    private var loopCount = 0
    /// 次の取得までの待ち。再読み込みで止めて起こす
    private var sleepTask: Task<Void, any Error>?
    /// 待ち始める前の状態とイベントの取得。再読み込みで止める
    var detailsTask: Task<ThreadDetailsFetcher.Results?, Never>?
    private var refreshWaiters = RefreshWaiters()
    var pendingRefreshCount: Int { refreshWaiters.count }  // テスト用

    init(
        accountID: AccountID, endpoints: APIEndpoints, client: GitHubAPIClient, tokens: any TokenProviding,
        participating: Bool = false, initialPhase: FeedPhase? = nil, carriedWait: CarriedWait? = nil,
        detailsTimeout: Duration = .seconds(20), sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
        now: @escaping @Sendable () -> Date = { Date() },
        onUpdate: @escaping @Sendable (FeedState) async -> Void
    ) {
        self.accountID = accountID
        self.endpoints = endpoints
        self.client = client
        self.tokens = tokens
        self.participating = participating
        // 作り直す前の止まった状態（再読み込みでの再開を待つ）か、取得の待ち（`CarriedWait`）を持ち越す
        state = (initialPhase ?? carriedWait?.initialPhase).map { FeedState(phase: $0, threads: []) } ?? .loading
        firstFetchNotBefore = carriedWait?.until
        self.detailsTimeout = detailsTimeout
        refreshWaiters = RefreshWaiters(lastAttemptStartedAt: carriedWait?.lastAttemptStartedAt)
        self.sleep = sleep
        self.now = now
        self.onUpdate = onUpdate
    }

    /// ポーリングを始める。すでに始めていれば何もしない。
    nonisolated func start() {
        loop.withLock { loop in
            guard loop.task == nil, !loop.discarded else { return }
            loop.task = Task { await self.run(refreshingTokenFirst: false) }
        }
    }

    /// 止まっているポーリングを、トークンを取り直してから再開する。`stop()` の後は何もせずに false を返す。
    @discardableResult
    nonisolated func resume() -> Bool {
        loop.withLock { loop in
            guard !loop.discarded else { return false }
            loop.task?.cancel()
            loop.task = Task { await self.run(refreshingTokenFirst: true) }
            return true
        }
    }

    /// 次の取得を `If-Modified-Since` なしにする。取得を早めはしない。
    nonisolated func requestUnconditionalFetch() {
        unconditionalRequested.store(true, ordering: .relaxed)
    }

    /// 再読み込み: 次の予定を待たずに（下限は `RefreshWaiters`）条件なしで取得し、終わるまで待つ。取得の途中なら、その後に
    /// もう 1 回取得する。止まっていれば再開して最初の取得を待つ。レート制限中とループが無いときは、早めずにすぐ戻る。
    func refreshNow() async {
        requestUnconditionalFetch()
        // レート制限の待ちの間だけ早めない（待ち終えて取得している途中なら、その後にもう 1 回取得する）
        guard !(state.phase.isRateLimited && sleepTask != nil) else { return }
        let stopped = state.phase.isStopped
        guard stopped || runningLoop != nil else { return }
        await withCheckedContinuation { continuation in
            refreshWaiters.add(continuation)
            guard stopped else {
                sleepTask?.cancel()
                detailsTask?.cancel()
                return
            }
            // 止めたループがまだ終わっていなくても、その終わりで新しい待ちを起こさないように、先に外す
            runningLoop = nil
            if !resume() { refreshWaiters.finish(all: true) }
        }
    }

    nonisolated func stop() {
        loop.withLock { loop in
            loop.task?.cancel()
            loop = (nil, true)
        }
    }

    private func run(refreshingTokenFirst: Bool) async {
        loopCount += 1
        let thisLoop = loopCount
        runningLoop = thisLoop
        defer { endLoop(thisLoop) }
        guard var refreshedToken = await beginLoop(refreshingTokenFirst: refreshingTokenFirst) else { return }
        while !Task.isCancelled {
            refreshWaiters.startAttempt(at: now())
            // トークンが無いのは、読み直しが一時的にトークンを捨てたときなど。失敗として待ってから確かめ直す
            let (result, number): (NotificationsFetchResult, Int)
            if let token = await tokens.currentToken(for: accountID) {
                (result, number) = await fetch(with: token)
            } else {
                Self.logger.error("No token for \(self.accountID)")
                (result, number) = (.failed(.noToken), fetchCount)
            }
            guard !Task.isCancelled else { return }

            switch await handle(result, fetchNumber: number, refreshedToken: refreshedToken) {
            case .stop:
                return
            case .retryNow:
                refreshedToken = true
            case .wait(let delay):
                // トークンが無くて送らなかった回は、取り直した直後かどうかを持ち越す（次の 401 で 2 回目の取り直しをしない）
                if result != .failed(.noToken) {
                    refreshedToken = false
                }
                await announceNextFetch(after: delay)
                refreshWaiters.finish()
                // 取ったら、次の取得の予定時刻を実際に待ち始める時刻から出し直す
                if await fillDetails() { await announceNextFetch(after: delay) }
                guard !Task.isCancelled, await pause(for: delay) else { return }
            }
        }
    }

    /// 次の取得まで `delay` 待つ。再読み込みの待ちがあれば、前の取得の開始から下限までの残りだけ待つ。止められたら false。
    private func pause(for delay: Duration) async -> Bool {
        // レート制限の待ちは早めない（取得の途中で押されていても）
        if state.phase.isRateLimited { refreshWaiters.finish(all: true) }
        if refreshWaiters.isEmpty {
            let task = Task { [sleep] in try await sleep(delay) }
            sleepTask = task
            _ = try? await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            sleepTask = nil
            guard !Task.isCancelled else { return false }
            if refreshWaiters.isEmpty { return true }
        }
        let remaining = refreshWaiters.remainingWait(now: now())
        await announceNextFetch(after: remaining ?? .zero)
        guard let remaining else { return true }
        return (try? await sleep(remaining)) != nil && !Task.isCancelled
    }

    /// ループが終わったら、再読み込みの待ちをすべて起こす。止めたループが新しいループの後に終わったときは何もしない。
    private func endLoop(_ thisLoop: Int) {
        guard runningLoop == thisLoop else { return }
        runningLoop = nil
        refreshWaiters.finish(all: true)
    }

    /// 1 回の取得をして、結果と取得の番号を返す。再読み込みの後と、最後に 200 で一覧を取り直してから間隔がたった後は
    /// `If-Modified-Since` を付けない。
    private func fetch(with token: AccessToken) async -> (NotificationsFetchResult, Int) {
        // 印は送る前に下ろす（取得中に押された再読み込みを、その前に始めた取得で消さないため）
        let requested = unconditionalRequested.exchange(false, ordering: .relaxed)
        let isDue =
            requested
            || PollSchedule.unconditionalFetchIsDue(
                lastFullFetch: lastFullFetch, now: now(), interval: Self.unconditionalFetchInterval)
        if isDue, lastModified != nil {
            Self.logger.info("Fetching \(self.accountID) without If-Modified-Since")
        }
        let ifModifiedSince = isDue ? nil : lastModified
        let number = fetchCount
        let startedAt = now()
        fetchCount += 1
        var result = await client.fetchNotifications(
            endpoints: endpoints, token: token, ifModifiedSince: ifModifiedSince, participating: participating)
        // 止められた（再開で新しいループに替わった）後に返った結果では、状態を書き換えない
        guard !Task.isCancelled else { return (result, number) }
        if case .updated(let fetched, let lastModified, let pollInterval, let scopes, let truncated) = result {
            // 隠すスレッドは取らない。取っている間に既読・Done・すべて既読にしたスレッドも一覧に戻さないよう、
            // 取った後に同じ番号と開始時刻でもう一度除く
            var threads = HiddenThreads.revealOrHide(
                fetched, hidden: &hidden, readThroughs: &readThroughs, fetchNumber: number, startedAt: startedAt)
            await prefetchNewDetails(in: threads, token: token, fetchNumber: number)
            guard !Task.isCancelled else { return (result, number) }
            threads = HiddenThreads.revealOrHide(
                threads, hidden: &hidden, readThroughs: &readThroughs, fetchNumber: number, startedAt: startedAt)
            // 隠したスレッドの記録も残す（既読にできずに一覧に戻ったときに、新着として取り直さないため）
            details.listed(fetched)
            result = .updated(
                threads: threads, lastModified: lastModified, pollInterval: pollInterval, scopes: scopes,
                truncated: truncated)
        }
        if case .updated = result {
            // 条件付きでも 200 なら全ページを取り直しているので、条件なしと同じく一覧は最新になる
            lastFullFetch = now()
        } else if requested {
            // 取り終えられなかったので、次の取得もまた条件なしにする
            unconditionalRequested.store(true, ordering: .relaxed)
        }
        return (result, number)
    }

    /// 次の取得の予定時刻を Diagnostics に出す。
    private func announceNextFetch(after delay: Duration) async {
        state.diagnostics.nextFetchAt = now().adding(delay)
        await publish(state)
    }

    /// 取得の結果を状態に反映し、次にすることを決める。`fetchNumber` は取得の番号、`refreshedToken` は直前にトークンを取り直したか。
    private func handle(_ result: NotificationsFetchResult, fetchNumber: Int, refreshedToken: Bool) async -> PollStep {
        recorder.recordFetch(result, number: fetchNumber, at: now(), in: &state)
        switch result {
        case .updated(let threads, let lastModified, let pollInterval, let scopes, _):
            if !scopesVerified {
                guard scopes.allowsNotifications else {
                    Self.logger.error("The token of \(self.accountID) lacks the repo and notifications scopes")
                    await stop(as: .scopeInsufficient)
                    return .stop
                }
                scopesVerified = true
            }
            self.lastModified = lastModified
            state.threads = details.attach(to: threads)
            return .wait(succeeded(pollInterval: pollInterval))
        case .notModified(let pollInterval):
            return .wait(succeeded(pollInterval: pollInterval))
        case .unauthorized:
            guard !refreshedToken else {
                Self.logger.error("\(self.accountID) is still unauthorized after refreshing the token")
                await tokens.discardToken(for: accountID)
                await stop(as: .unauthorized)
                return .stop
            }
            return await refreshToken() ? .retryNow : .stop
        case .rateLimited(let retryAt):
            let delay = PollSchedule.afterRateLimit(retryAt: retryAt, now: now())
            state.phase = .retrying(after: delay, rateLimited: true, now: now())
            return .wait(delay)
        case .forbidden(let scopes) where scopes.scopes != nil && !scopes.allowsNotifications:
            Self.logger.error("\(self.accountID) was refused for lacking the repo and notifications scopes")
            await stop(as: .scopeInsufficient)
            return .stop
        case .failed(.noToken):
            // 読み直しや取り直しの途中で一時的にトークンが無いだけのことが多いので、待ち時間は延ばさない
            let delay = PollSchedule.afterSuccess(pollInterval: nil)
            state.phase = .retrying(after: delay, rateLimited: false, now: now())
            return .wait(delay)
        case .forbidden, .invalidRequest, .failed:
            consecutiveFailures += 1
            let delay = PollSchedule.afterFailure(consecutiveFailures: consecutiveFailures)
            state.phase = .retrying(after: delay, rateLimited: false, now: now())
            return .wait(delay)
        }
    }

    func publish(_ state: FeedState) async {
        self.state = state
        await onUpdate(state)
    }
}

// トークンの取り直しと、取得の結果による状態の更新
extension AccountPoller {
    /// トークンを取り直し、条件付きリクエストとスコープの確認をやり直す。取れなければ「認証エラー」で止める。
    private func refreshToken() async -> Bool {
        // 前のトークンのスコープは、取り直せたかどうかにかかわらず捨てる
        state.diagnostics.scopes = nil
        guard await tokens.refreshToken(for: accountID) != nil else {
            Self.logger.error("Could not refresh the token of \(self.accountID)")
            await stop(as: .unauthorized)
            return false
        }
        lastModified = nil
        scopesVerified = false
        return true
    }

    private func succeeded(pollInterval: Int?) -> Duration {
        consecutiveFailures = 0
        state.phase = .loaded(updatedAt: now())
        state.diagnostics.recordSuccess(at: now(), pollInterval: pollInterval)
        return PollSchedule.afterSuccess(pollInterval: pollInterval)
    }

    /// 止まった状態にする。スレッドは捨てる（Diagnostics の値は `FeedRecorder.stopped` で持ち越す）。
    private func stop(as phase: FeedPhase) async {
        state = recorder.stopped(as: phase, from: state)
        readThroughs.removeAll()
        details.reset()
        lastModified = nil
        scopesVerified = false
        consecutiveFailures = 0
        await publish(state)
    }
}

// 最初の取得の待ち
extension AccountPoller {
    /// ループの最初。再開ならトークンを取り直し、そうでなければ `firstFetchNotBefore` まで待つ（ループの中で待つので、
    /// レート制限の待ちでなければ再読み込みで早められる）。止めるなら nil、続けるならトークンを取り直したか。
    fileprivate func beginLoop(refreshingTokenFirst: Bool) async -> Bool? {
        if refreshingTokenFirst {
            // トークンを取り直すので、前のトークンのスコープは出さない
            state.diagnostics.scopes = nil
            await publish(recorder.stopped(as: .loading, from: state))
            return await refreshToken() ? true : nil
        }
        guard let firstFetchNotBefore, firstFetchNotBefore > now() else { return false }
        let delay = Duration.seconds(firstFetchNotBefore.timeIntervalSince(now()))
        await announceNextFetch(after: delay)
        return await pause(for: delay) ? false : nil
    }
}
