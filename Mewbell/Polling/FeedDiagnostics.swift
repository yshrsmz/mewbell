import Foundation

/// 取得と操作の失敗の種類。トークン、URL、ヘッダーの値、レスポンスボディは持たない。
enum FailureKind: Sendable, Equatable {
    case network
    /// 想定していない状態コード（数字だけ）
    case httpStatus(Int)
    case redirect
    case bodyTooLarge
    case malformedBody
    /// トークンをメモリに持っていなかった（送っていない）
    case noToken
    case rateLimited
    /// 401
    case unauthorized
    /// トークンを送ってよい URL ではなかった（送っていない）
    case rejectedURL

    init(_ failure: FetchFailure) {
        self =
            switch failure {
            case .rejectedURL: .rejectedURL
            case .redirect: .redirect
            case .bodyTooLarge: .bodyTooLarge
            case .network: .network
            case .unexpectedStatus(let status): .httpStatus(status)
            case .malformedBody: .malformedBody
            case .noToken: .noToken
            }
    }

    /// 取得の結果の失敗の種類。成功（200 / 304）なら nil。
    init?(_ result: NotificationsFetchResult) {
        switch result {
        case .updated, .notModified: return nil
        case .unauthorized: self = .unauthorized
        case .rateLimited: self = .rateLimited
        case .forbidden: self = .httpStatus(403)
        case .invalidRequest: self = .httpStatus(422)
        case .failed(let failure): self.init(failure)
        }
    }

    /// 操作の結果の失敗の種類。成功なら nil。
    init?(_ result: ThreadActionResult) {
        switch result {
        case .succeeded: return nil
        case .unauthorized: self = .unauthorized
        case .rateLimited: self = .rateLimited
        case .failed(let failure): self.init(failure)
        }
    }
}

/// 失敗を記録する操作。
enum ThreadActionKind: Sendable, Equatable {
    case read
    case done
    case markAllRead

    init(_ action: ThreadAction) {
        self =
            switch action {
            case .read: .read
            case .done: .done
            }
    }
}

/// 失敗と、その時刻。
struct TimedFailure: Sendable, Equatable {
    var kind: FailureKind
    var occurredAt: Date
}

/// 既読・Done・すべて既読の失敗。
struct ActionFailure: Sendable, Equatable {
    var action: ThreadActionKind
    var kind: FailureKind
    var occurredAt: Date
}

/// 成功の後に使ったポーリングの間隔。
struct PollIntervalInfo: Sendable, Equatable {
    var seconds: Int
    /// `X-Poll-Interval` に従った（false なら既定の 60 秒）
    var fromHeader: Bool
}

extension PollIntervalInfo {
    /// 取得の結果の `X-Poll-Interval` から決める（間隔は `PollSchedule.afterSuccess` が決めたもの）。
    init(pollInterval: Int?) {
        self.init(
            seconds: Int(PollSchedule.afterSuccess(pollInterval: pollInterval).components.seconds),
            fromHeader: (pollInterval ?? 0) >= PollSchedule.minimumInterval)
    }
}

/// Diagnostics に出す、アカウントの取得の値。
struct FeedDiagnostics: Sendable, Equatable {
    /// 最後に取得できた（200 / 304）時刻。失敗して待っている間も残す
    var lastFetchedAt: Date?
    /// 次の取得の予定時刻（止まっているときは nil）
    var nextFetchAt: Date?
    var pollInterval: PollIntervalInfo?
    /// 今のトークンで最後に受け取った `X-OAuth-Scopes`（まだ受け取っていなければ nil）
    var scopes: OAuthScopes?
    var lastFetchFailure: TimedFailure?
    var lastActionFailure: ActionFailure?

    /// 取得できた（200 / 304）時刻と、その後に使う間隔を記録する。
    mutating func recordSuccess(at date: Date, pollInterval: Int?) {
        lastFetchedAt = date
        self.pollInterval = PollIntervalInfo(pollInterval: pollInterval)
    }
}
