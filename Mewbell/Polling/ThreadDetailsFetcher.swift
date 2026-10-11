import Foundation
import os

/// 複数のスレッドの件名の状態とイベントを、同時に `concurrency` 件まで取る（polling「スレッドのイベントの取得」）。
/// 状態を持たない。`AccountPoller` の中から呼ぶ。
struct ThreadDetailsFetcher: Sendable {
    /// 知らせる前に取る新着の上限
    static let prefetchLimit = 10
    /// 知らせた後に取るスレッドの上限（1 回の取得ごと）
    static let fillLimit = 30
    /// 同時に取るスレッドの上限
    static let concurrency = 4
    private static let logger = Logger(category: "Polling")

    let client: GitHubAPIClient
    let endpoints: APIEndpoints

    private enum Outcome: Sendable {
        case fetched(NotificationThread, ThreadDetailsFetchResult)
        case timedOut
    }

    /// `threads` を順に取り、終わった分の結果を返す。`timeout` を過ぎたら残りを止める（止めた分は返さない）。
    /// レート制限が返ったら、まだ始めていない分は取らない。
    func fetch(
        _ threads: [NotificationThread], token: AccessToken, timeout: Duration?
    ) async -> [(NotificationThread, ThreadDetailsFetchResult)] {
        let client = client
        let endpoints = endpoints
        return await withTaskGroup(of: Outcome.self) { group in
            if let timeout {
                group.addTask {
                    try? await Task.sleep(for: timeout)
                    return .timedOut
                }
            }
            var queue = threads[...]
            var inFlight = 0
            func startNext() {
                guard let thread = queue.popFirst() else { return }
                group.addTask {
                    .fetched(thread, await client.fetchDetails(for: thread, endpoints: endpoints, token: token))
                }
                inFlight += 1
            }
            for _ in 0..<Self.concurrency {
                startNext()
            }
            var results: [(NotificationThread, ThreadDetailsFetchResult)] = []
            while inFlight > 0, let outcome = await group.next() {
                switch outcome {
                case .timedOut:
                    Self.logger.info("Stopped fetching thread details on \(endpoints.host) at the time limit")
                    group.cancelAll()
                    return results
                case .fetched(let thread, let result):
                    inFlight -= 1
                    results.append((thread, result))
                    if case .rateLimited = result {
                        Self.logger.info("Fetching thread details on \(endpoints.host) was rate limited")
                        queue.removeAll()
                    }
                    startNext()
                }
            }
            group.cancelAll()
            return results
        }
    }
}
