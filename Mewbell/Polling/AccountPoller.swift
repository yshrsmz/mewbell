import Foundation
import Synchronization
import os

/// 1 アカウントの通知をポーリングする。ループは 1 つだけ走らせる。
actor AccountPoller {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private static let logger = Logger(category: "Polling")

    let accountID: AccountID
    private let endpoints: APIEndpoints
    private let client: GitHubAPIClient
    private let tokens: any TokenProviding
    private let sleep: Sleep
    private let now: @Sendable () -> Date
    private let onUpdate: @Sendable (FeedState) async -> Void

    /// 走っているループ。actor に入らずに起動・停止できるように、ロックで持つ
    private nonisolated let loop = Mutex<Task<Void, Never>?>(nil)

    private var state = FeedState.loading
    /// 最後にすべてのページを取り終えた 200 の `Last-Modified`
    private var lastModified: String?
    /// 今のトークンでスコープを確かめたか
    private var scopesVerified = false
    private var consecutiveFailures = 0

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
            guard let token = await tokens.currentToken(for: accountID) else {
                Self.logger.error("No token for \(self.accountID)")
                await stop(as: .unauthorized)
                return
            }
            let result = await client.fetchNotifications(
                endpoints: endpoints, token: token, ifModifiedSince: lastModified)
            guard !Task.isCancelled else { return }

            switch await handle(result, refreshedToken: refreshedToken) {
            case .stop:
                return
            case .retryNow:
                refreshedToken = true
            case .wait(let delay):
                refreshedToken = false
                await publish(state)
                do {
                    try await sleep(delay)
                } catch {
                    return
                }
            }
        }
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
        await publish(state)
    }

    private func publish(_ state: FeedState) async {
        self.state = state
        await onUpdate(state)
    }
}
