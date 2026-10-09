import Foundation
import Synchronization
import os

/// 1 アカウントの通知をポーリングする。ループは 1 つだけ走らせる。
actor AccountPoller {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private static let logger = Logger(category: "Polling")
    /// 条件なしの取得の間隔。`Last-Modified` は未読の `updated_at` の最新値なので、それより古いスレッドの増減は
    /// `304` に隠れる。その分のずれを、この間隔で取り直して直す
    static let unconditionalFetchInterval: TimeInterval = 300

    let accountID: AccountID
    private let endpoints: APIEndpoints
    private let client: GitHubAPIClient
    private let tokens: any TokenProviding
    private let sleep: Sleep
    private let now: @Sendable () -> Date
    private let onUpdate: @Sendable (FeedState) async -> Void

    /// 走っているループ。actor に入らずに起動・停止できるように、ロックで持つ
    private nonisolated let loop = Mutex<Task<Void, Never>?>(nil)
    /// 次の取得を条件なしにする印（再読み込み）。actor に入らずに立てられるように、アトミックに持つ
    private nonisolated let unconditionalRequested = Atomic(false)

    private var state = FeedState.loading
    /// 最後にすべてのページを取り終えた 200 の `Last-Modified`
    private var lastModified: String?
    /// 最後に 200 で全ページを取り終えた時刻（`If-Modified-Since` を付けた取得でも 200 なら一覧はすべて取り直される）
    private var lastFullFetch: Date?
    /// 今のトークンでスコープを確かめたか
    private var scopesVerified = false
    private var consecutiveFailures = 0
    /// 始めた取得の数（次に始める取得の番号）
    private var fetchCount = 0
    /// 既読にしたので、取得の結果から取り除いているスレッド
    private var hidden: [String: HiddenUntil] = [:]
    /// スレッドごとの、終わっていない既読化のリクエストの数（同じスレッドを続けて既読にしたとき、先に終わった分で隠すのをやめないように）
    private var readsInFlight: [String: Int] = [:]

    /// 既読にしたスレッドを、いつまで取得の結果から取り除くか。
    private enum HiddenUntil {
        /// 既読化のリクエストが終わるまで
        case requestFinishes
        /// この番号以降の取得の 200 が出るまで（既読化の後に始めた取得なら、結果をそのまま信じてよい）
        case fetch(Int)
    }

    init(
        accountID: AccountID, endpoints: APIEndpoints, client: GitHubAPIClient, tokens: any TokenProviding,
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }, now: @escaping @Sendable () -> Date = { Date() },
        onUpdate: @escaping @Sendable (FeedState) async -> Void
    ) {
        self.accountID = accountID
        self.endpoints = endpoints
        self.client = client
        self.tokens = tokens
        self.sleep = sleep
        self.now = now
        self.onUpdate = onUpdate
    }

    /// ポーリングを始める。すでに始めていれば何もしない。
    nonisolated func start() {
        loop.withLock { loop in
            guard loop == nil else { return }
            loop = Task { await self.run(refreshingTokenFirst: false) }
        }
    }

    /// 止まっているポーリングを、トークンを取り直してから再開する（再読み込みボタン）。
    nonisolated func resume() {
        loop.withLock { loop in
            loop?.cancel()
            loop = Task { await self.run(refreshingTokenFirst: true) }
        }
    }

    /// 次の取得を `If-Modified-Since` なしにする（再読み込みボタン）。取得を早めはしない。
    nonisolated func requestUnconditionalFetch() {
        unconditionalRequested.store(true, ordering: .relaxed)
    }

    /// スレッドを既読にする。一覧からすぐに外し、既読化のリクエストを送り、次の取得を条件なしにする。
    /// 止まっているときとトークンが無いときは送らない（次の条件なしの取得で、未読のままなら一覧に戻る）。
    func markRead(threadID: String) async {
        hidden[threadID] = .requestFinishes
        readsInFlight[threadID, default: 0] += 1
        if state.threads.contains(where: { $0.id == threadID }) {
            state.threads.removeAll { $0.id == threadID }
            await publish(state)
        }
        if !state.phase.isStopped, let token = await tokens.currentToken(for: accountID) {
            let result = await client.markThreadRead(endpoints: endpoints, token: token, threadID: threadID)
            if result != .read {
                Self.logger.error("Could not mark a thread of \(self.accountID) as read: \(String(describing: result))")
            }
        }
        // 既読化の結果が 304 に隠れないように、また失敗したスレッドが一覧に戻るように、次は条件なしで取り直す
        readsInFlight[threadID, default: 1] -= 1
        if readsInFlight[threadID] == 0 {
            readsInFlight[threadID] = nil
            hidden[threadID] = .fetch(fetchCount)
        }
        unconditionalRequested.store(true, ordering: .relaxed)
    }

    nonisolated func stop() {
        loop.withLock { loop in
            loop?.cancel()
            loop = nil
        }
    }

    /// 1 回の取得の後にすること。
    private enum Step {
        /// 待ってから次の取得をする
        case wait(Duration)
        /// トークンを取り直したので、すぐに取得をやり直す
        case retryNow
        /// 止まった
        case stop
    }

    private func run(refreshingTokenFirst: Bool) async {
        var refreshedToken = false
        if refreshingTokenFirst {
            await publish(.loading)
            guard await refreshToken() else { return }
            refreshedToken = true
        }
        while !Task.isCancelled {
            // トークンが無いのは、読み直しが一時的にトークンを捨てたときなど。失敗として待ってから確かめ直す
            let result: NotificationsFetchResult
            if let token = await tokens.currentToken(for: accountID) {
                result = await fetch(with: token)
            } else {
                Self.logger.error("No token for \(self.accountID)")
                result = .failed(.noToken)
            }
            guard !Task.isCancelled else { return }

            switch await handle(result, refreshedToken: refreshedToken) {
            case .stop:
                return
            case .retryNow:
                refreshedToken = true
            case .wait(let delay):
                // トークンが無くて送らなかった回は、取り直した直後かどうかを持ち越す（次の 401 で 2 回目の取り直しをしない）
                if result != .failed(.noToken) {
                    refreshedToken = false
                }
                await publish(state)
                do {
                    try await sleep(delay)
                } catch {
                    return
                }
            }
        }
    }

    /// 1 回の取得をする。再読み込みの後と、最後に 200 で一覧を取り直してから間隔がたった後は `If-Modified-Since` を付けない。
    private func fetch(with token: AccessToken) async -> NotificationsFetchResult {
        // 印は送る前に下ろす（取得中に押された再読み込みを、その前に始めた取得で消さないため）
        let requested = unconditionalRequested.exchange(false, ordering: .relaxed)
        let isDue = requested || periodicUnconditionalFetchIsDue
        if isDue, lastModified != nil {
            Self.logger.info("Fetching \(self.accountID) without If-Modified-Since")
        }
        let ifModifiedSince = isDue ? nil : lastModified
        let number = fetchCount
        fetchCount += 1
        var result = await client.fetchNotifications(
            endpoints: endpoints, token: token, ifModifiedSince: ifModifiedSince)
        if case .updated(let threads, let lastModified, let pollInterval, let scopes) = result {
            result = .updated(
                threads: revealOrHide(threads, fetchNumber: number), lastModified: lastModified,
                pollInterval: pollInterval, scopes: scopes)
        }
        // 止められた（再開で新しいループに替わった）後に返った結果では、状態を書き換えない
        guard !Task.isCancelled else { return result }
        if case .updated = result {
            // 条件付きでも 200 なら全ページを取り直しているので、条件なしと同じく一覧は最新になる
            lastFullFetch = now()
        } else if requested {
            // 取り終えられなかったので、次の取得もまた条件なしにする
            unconditionalRequested.store(true, ordering: .relaxed)
        }
        return result
    }

    /// 既読化の後に始めた取得の結果なら隠すのをやめ、そうでなければ既読にしたスレッドを取り除く。
    private func revealOrHide(_ threads: [NotificationThread], fetchNumber: Int) -> [NotificationThread] {
        hidden = hidden.filter { _, until in
            guard case .fetch(let first) = until else { return true }
            return fetchNumber < first
        }
        return threads.filter { hidden[$0.id] == nil }
    }

    /// 最後に 200 で一覧を取り直してから間隔がたったか。時計が戻ったとき（差が負）も、たったものとして扱う
    /// （戻った分だけ取り直しが遅れないように）。`lastModified` と `lastFullFetch` はどちらも 200 で入るので、
    /// トークンの取り直しや停止で `lastModified` を消せば、時刻を消さなくても次は条件なしになる
    private var periodicUnconditionalFetchIsDue: Bool {
        guard let lastFullFetch else { return true }
        let elapsed = now().timeIntervalSince(lastFullFetch)
        return elapsed >= Self.unconditionalFetchInterval || elapsed < 0
    }

    /// 取得の結果を状態に反映し、次にすることを決める。`refreshedToken` は直前にトークンを取り直したか。
    private func handle(_ result: NotificationsFetchResult, refreshedToken: Bool) async -> Step {
        switch result {
        case .updated(let threads, let lastModified, let pollInterval, let scopes):
            if !scopesVerified {
                guard scopes.allowsNotifications else {
                    Self.logger.error("The token of \(self.accountID) lacks the repo and notifications scopes")
                    await stop(as: .scopeInsufficient)
                    return .stop
                }
                scopesVerified = true
            }
            self.lastModified = lastModified
            state.threads = threads
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
            state.phase = retrying(after: delay, rateLimited: true)
            return .wait(delay)
        case .forbidden(let scopes) where scopes.scopes != nil && !scopes.allowsNotifications:
            Self.logger.error("\(self.accountID) was refused for lacking the repo and notifications scopes")
            await stop(as: .scopeInsufficient)
            return .stop
        case .failed(.noToken):
            // 読み直しや取り直しの途中で一時的にトークンが無いだけのことが多いので、待ち時間は延ばさない
            let delay = PollSchedule.afterSuccess(pollInterval: nil)
            state.phase = retrying(after: delay, rateLimited: false)
            return .wait(delay)
        case .forbidden, .invalidRequest, .failed:
            consecutiveFailures += 1
            let delay = PollSchedule.afterFailure(consecutiveFailures: consecutiveFailures)
            state.phase = retrying(after: delay, rateLimited: false)
            return .wait(delay)
        }
    }

    /// トークンを取り直し、条件付きリクエストとスコープの確認をやり直す。取れなければ「認証エラー」で止める。
    private func refreshToken() async -> Bool {
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
        return PollSchedule.afterSuccess(pollInterval: pollInterval)
    }

    private func retrying(after delay: Duration, rateLimited: Bool) -> FeedPhase {
        .retrying(nextAttempt: now().addingTimeInterval(Double(delay.components.seconds)), rateLimited: rateLimited)
    }

    /// 止まった状態にする。スレッドは捨てる。
    private func stop(as phase: FeedPhase) async {
        state = FeedState(phase: phase, threads: [])
        lastModified = nil
        scopesVerified = false
        consecutiveFailures = 0
        await publish(state)
    }

    private func publish(_ state: FeedState) async {
        self.state = state
        await onUpdate(state)
    }
}
