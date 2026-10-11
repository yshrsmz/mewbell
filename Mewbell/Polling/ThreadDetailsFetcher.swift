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

    typealias Results = [(NotificationThread, ThreadDetailsFetchResult)]

    let client: GitHubAPIClient
    let endpoints: APIEndpoints

    private enum Outcome: Sendable {
        case fetched(NotificationThread, ThreadDetailsFetchResult)
        case timedOut
        /// 取得ごと止められた（再読み込みなど）
        case cancelled
    }

    /// `threads` を順に取り、結果を返す。`timeout` を過ぎたら残りを止め、始めていて終わらなかった分は一時的な失敗として返す
    /// （始めていない分は返さない）。呼び出し元のタスクごと止められたら、それまでに終わった分だけを返す。レート制限が返ったら、まだ始めていない分は取らない。
    func fetch(
        _ threads: [NotificationThread], token: AccessToken, timeout: Duration
    ) async -> [(NotificationThread, ThreadDetailsFetchResult)] {
        let client = client
        let endpoints = endpoints
        return await withTaskGroup(of: Outcome.self) { group in
            group.addTask {
                // 止められたときは、打ち切りと区別する（始めた分を一時的な失敗にしない）
                (try? await Task.sleep(for: timeout)) == nil ? .cancelled : .timedOut
            }
            var queue = threads[...]
            // 始めて、まだ終わっていないスレッド
            var running: [String: NotificationThread] = [:]
            func startNext() {
                guard let thread = queue.popFirst() else { return }
                group.addTask {
                    .fetched(thread, await client.fetchDetails(for: thread, endpoints: endpoints, token: token))
                }
                running[thread.id] = thread
            }
            for _ in 0..<Self.concurrency {
                startNext()
            }
            var results: [(NotificationThread, ThreadDetailsFetchResult)] = []
            while !running.isEmpty, let outcome = await group.next() {
                switch outcome {
                case .timedOut:
                    Self.logger.info("Stopped fetching thread details on \(endpoints.host) at the time limit")
                    group.cancelAll()
                    let timedOut = FetchFailure.network(code: URLError.Code.timedOut.rawValue)
                    return results + running.values.map { ($0, .failed(timedOut)) }
                case .cancelled:
                    group.cancelAll()
                    return results
                // 止められた後に終わった取得は、止めたことで失敗したものなので返さない
                case .fetched where Task.isCancelled:
                    group.cancelAll()
                    return results
                case .fetched(let thread, let result):
                    running[thread.id] = nil
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
