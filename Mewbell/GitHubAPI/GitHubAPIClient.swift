import Foundation
import os

/// `X-OAuth-Scopes` の値。
struct OAuthScopes: Sendable, Equatable {
    /// ヘッダーが無いときは nil（classic 系でないトークン）
    let scopes: Set<String>?

    init(header: String?) {
        scopes = header.map { value in
            Set(value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        }
    }

    /// 通知を読めるスコープ（`repo` か `notifications`）を含むか。ヘッダーが無ければ false。
    var allowsNotifications: Bool {
        guard let scopes else { return false }
        return scopes.contains("repo") || scopes.contains("notifications")
    }
}

/// 取得の失敗の種類。トークンやレスポンスボディは持たない。
enum FetchFailure: Error, Equatable, Sendable {
    /// トークンを送ってよい URL ではなかった（送っていない）
    case rejectedURL
    case redirect
    case bodyTooLarge
    case network(code: Int)
    case unexpectedStatus(Int)
    case malformedBody
    /// トークンをメモリに持っていなかった（送っていない）
    case noToken
}

enum NotificationsFetchResult: Sendable, Equatable {
    /// `truncated` は 10 ページ目にも `rel="next"` があった（それより古い未読を取得していない）
    case updated(
        threads: [NotificationThread], lastModified: String?, pollInterval: Int?, scopes: OAuthScopes, truncated: Bool)
    case notModified(pollInterval: Int?)
    /// 401
    case unauthorized
    /// レート制限の 403 / 429（`retryAt` まで待つ。nil は待ち時間のヘッダーが無く、待ち時間が分からない）
    case rateLimited(retryAt: Date?)
    /// レート制限でない 403。`X-OAuth-Scopes` があれば、スコープ不足かどうかの判断に使う
    case forbidden(scopes: OAuthScopes)
    /// 422
    case invalidRequest
    case failed(FetchFailure)
}

/// スレッドの既読化・Done・すべて既読の結果。
enum ThreadActionResult: Sendable, Equatable {
    /// 操作ごとの成功の状態コード（既読は `205` / `304` / `404`、Done は `204` / `404`、すべて既読は `202` / `205` / `304`）
    case succeeded
    /// 401
    case unauthorized
    /// レート制限の 403 / 429
    case rateLimited
    /// そのほかの状態コード、リダイレクト、通信の失敗、送らなかった
    case failed(FetchFailure)
}

/// GitHub の REST API のクライアント。リクエストはすべて関所の `APIGateway` を通して送る。
/// 状態を持たない。`AccountPoller` の中から呼ぶ。
struct GitHubAPIClient: Sendable {
    static let pageLimit = 10
    static let perPage = 50
    /// 1 回の取得で取るスレッドの上限（これを超える古い未読は取らない）
    static let threadLimit = pageLimit * perPage
    private static let logger = Logger(category: "GitHubAPI")

    /// 送るのはこの関所だけ（`GitHubAPIClient+ThreadDetails.swift` の extension も使う）
    let gateway: APIGateway
    /// レート制限の解ける時刻（`Retry-After`、`X-RateLimit-Reset`、どちらも無いときの今）を出すための現在時刻
    let now: @Sendable () -> Date

    init(transport: any HTTPTransport, now: @escaping @Sendable () -> Date = { Date() }) {
        gateway = APIGateway(transport: transport)
        self.now = now
    }

    /// 未読の通知を、`rel="next"` をたどって取得する。すべてのページに同じ `token` を付ける。
    func fetchNotifications(
        endpoints: APIEndpoints, token: AccessToken, ifModifiedSince: String?, participating: Bool = false
    ) async -> NotificationsFetchResult {
        var components = URLComponents(
            url: endpoints.apiURL(path: "notifications"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "all", value: "false"),
            URLQueryItem(name: "participating", value: participating ? "true" : "false"),
            URLQueryItem(name: "per_page", value: String(Self.perPage)),
        ]
        guard var url = components?.url else { return .failed(.rejectedURL) }

        var threads: [NotificationThread] = []
        var seenIDs: Set<String> = []
        var firstResponse: HTTPResponse?
        var page = 1
        while true {
            let response: HTTPResponse
            switch await gateway.send(
                url, method: "GET", endpoints: endpoints, token: token,
                ifModifiedSince: page == 1 ? ifModifiedSince : nil)
            {
            case .success(let value): response = value
            case .failure(let failure): return .failed(failure)
            }

            switch response.statusCode {
            case 200:
                break
            case 304 where page == 1 && ifModifiedSince != nil:
                return .notModified(pollInterval: Self.pollInterval(response))
            default:
                return classifyFailure(response)
            }
            guard let pageThreads = NotificationThread.decodeList(from: response.body, endpoints: endpoints) else {
                Self.logger.error("Could not decode notifications page \(page, privacy: .private)")
                return .failed(.malformedBody)
            }
            // ページの取得の間に新着があると、ページの境目がずれて同じスレッドが 2 回返ることがある
            threads += pageThreads.filter { seenIDs.insert($0.id).inserted }
            let first = firstResponse ?? response
            firstResponse = first
            let next = LinkHeader.nextURL(in: response.header("Link"))
            guard page < Self.pageLimit, let next else {
                // 続きが無いか、ページの上限まで取った（それ以上は取らず、取った分で一覧を作る）
                return .updated(
                    threads: threads, lastModified: first.header("Last-Modified"),
                    pollInterval: Self.pollInterval(first), scopes: OAuthScopes(header: first.header("X-OAuth-Scopes")),
                    truncated: next != nil)
            }
            url = next
            page += 1
        }
    }

    /// スレッドを既読にする（`PATCH /notifications/threads/{id}`）。`threadID` が数字でなければ送らない。
    func markThreadRead(endpoints: APIEndpoints, token: AccessToken, threadID: String) async -> ThreadActionResult {
        await sendThreadAction(
            method: "PATCH", endpoints: endpoints, token: token, threadID: threadID, success: [205, 304, 404])
    }

    /// スレッドを Done にする（`DELETE /notifications/threads/{id}`）。`threadID` が数字でなければ送らない。
    func markThreadDone(endpoints: APIEndpoints, token: AccessToken, threadID: String) async -> ThreadActionResult {
        await sendThreadAction(
            method: "DELETE", endpoints: endpoints, token: token, threadID: threadID, success: [204, 404])
    }

    /// API に送る日時の書き方（UTC、秒まで、末尾が `Z`）
    static let apiDateFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: false, timeZone: .gmt)

    /// アカウントの通知のうち、`lastReadAt` 以前に更新されたものをすべて既読にする（`PUT /notifications`）。
    /// `202` は GitHub が後から非同期に既読にするという意味で、成功として扱う。
    func markAllRead(endpoints: APIEndpoints, token: AccessToken, lastReadAt: Date) async -> ThreadActionResult {
        // 秒まで・UTC（呼び出し元は隠す範囲も秒に揃えている）
        let body = MarkAllReadBody(lastReadAt: lastReadAt.formatted(Self.apiDateFormat), read: true)
        guard let data = try? JSONEncoder().encode(body) else { return .failed(.malformedBody) }
        return await sendAction(
            endpoints.apiURL(path: "notifications"), method: "PUT", endpoints: endpoints, token: token,
            success: [202, 205, 304], body: data)
    }

    private func sendThreadAction(
        method: String, endpoints: APIEndpoints, token: AccessToken, threadID: String, success: Set<Int>
    ) async -> ThreadActionResult {
        guard ThreadID.isValid(threadID) else {
            Self.logger.error("Refused to send \(method) for a thread with an invalid ID")
            return .failed(.rejectedURL)
        }
        return await sendAction(
            endpoints.apiURL(path: "notifications/threads/\(threadID)"), method: method, endpoints: endpoints,
            token: token, success: success)
    }

    /// 操作のリクエストを送り、レスポンスを分類する。
    private func sendAction(
        _ url: URL, method: String, endpoints: APIEndpoints, token: AccessToken, success: Set<Int>,
        body: Data? = nil
    ) async -> ThreadActionResult {
        switch await gateway.send(
            url, method: method, endpoints: endpoints, token: token, ifModifiedSince: nil, body: body)
        {
        case .success(let response): classifyAction(response, success: success)
        case .failure(let failure): .failed(failure)
        }
    }

    private func classifyAction(_ response: HTTPResponse, success: Set<Int>) -> ThreadActionResult {
        switch response.statusCode {
        case let status where success.contains(status):
            return .succeeded
        case 401:
            return .unauthorized
        case 403, 429:
            return rateLimit(response) == nil ? .failed(.unexpectedStatus(response.statusCode)) : .rateLimited
        default:
            return .failed(.unexpectedStatus(response.statusCode))
        }
    }

    private func classifyFailure(_ response: HTTPResponse) -> NotificationsFetchResult {
        switch response.statusCode {
        case 401:
            return .unauthorized
        case 403, 429:
            switch rateLimit(response) {
            case .until(let retryAt): return .rateLimited(retryAt: retryAt)
            case .unknownWait: return .rateLimited(retryAt: nil)
            case nil: return .forbidden(scopes: OAuthScopes(header: response.header("X-OAuth-Scopes")))
            }
        case 422:
            return .invalidRequest
        default:
            return .failed(.unexpectedStatus(response.statusCode))
        }
    }

    /// 403 / 429 のレート制限の分け方。
    enum RateLimit {
        /// 待ち時間のヘッダーがあり、制限が解ける時刻が分かる
        case until(Date)
        /// 待ち時間のヘッダーが無い（429、または本文が二次レート制限を示す 403）
        case unknownWait
    }

    /// 403 / 429 のレスポンスのレート制限。レート制限でない 403 なら nil。
    /// 一覧の取得・操作・状態とイベントの取得の分類で使い、判定を揃える。
    /// `Retry-After` が秒数として読めればその秒数後、`X-RateLimit-Remaining: 0` なら `X-RateLimit-Reset`（無ければ今）。
    func rateLimit(_ response: HTTPResponse) -> RateLimit? {
        if let seconds = Self.retryAfterSeconds(response) {
            return .until(now().addingTimeInterval(TimeInterval(max(seconds, 0))))
        }
        if response.header("X-RateLimit-Remaining") == "0" {
            let reset = response.header("X-RateLimit-Reset")
                .flatMap { TimeInterval($0) }
                .map(Date.init(timeIntervalSince1970:))
            return .until(reset ?? now())
        }
        if response.statusCode == 429 || Self.isSecondaryRateLimit(response) { return .unknownWait }
        return nil
    }

    /// 二次レート制限の 403 か（本文の `message` が「secondary rate limit」を含む）。本文は見分けるのにだけ使い、残さない。
    private static func isSecondaryRateLimit(_ response: HTTPResponse) -> Bool {
        struct Message: Decodable { let message: String? }
        let message = (try? JSONDecoder().decode(Message.self, from: response.body))?.message
        return message?.localizedCaseInsensitiveContains("secondary rate limit") == true
    }

    private static func retryAfterSeconds(_ response: HTTPResponse) -> Int? {
        response.header("Retry-After").flatMap { Int($0) }
    }

    private static func pollInterval(_ response: HTTPResponse) -> Int? {
        response.header("X-Poll-Interval").flatMap { Int($0) }
    }
}

/// `PUT /notifications` のボディ。トークンを含めない。
private struct MarkAllReadBody: Encodable {
    let lastReadAt: String
    let read: Bool

    enum CodingKeys: String, CodingKey {
        case lastReadAt = "last_read_at"
        case read
    }
}
