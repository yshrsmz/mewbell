// swiftlint:disable file_length
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
    /// レート制限の 403（`retryAt` まで待つ）
    case rateLimited(retryAt: Date)
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

/// GitHub の REST API のクライアント。トークンを `Authorization` に付けるのはこの型だけ。
/// 状態を持たない。`AccountPoller` の中から呼ぶ。
struct GitHubAPIClient: Sendable {
    static let pageLimit = 10
    static let perPage = 50
    /// 1 回の取得で取るスレッドの上限（これを超える古い未読は取らない）
    static let threadLimit = pageLimit * perPage
    static let bodyLimit = 5 * 1024 * 1024
    private static let logger = Logger(category: "GitHubAPI")
    private static let userAgent =
        "Mewbell/\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")"

    /// 送るのは `send` だけ（オリジン検査とリダイレクトの扱いを迂回させないため、外に見せない）
    private let transport: any HTTPTransport
    /// レート制限の解ける時刻（`Retry-After`、`X-RateLimit-Reset`、どちらも無いときの今）を出すための現在時刻
    private let now: @Sendable () -> Date

    init(transport: any HTTPTransport, now: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport
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
            switch await send(
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

    /// アカウントの通知のうち、`lastReadAt` 以前に更新されたものをすべて既読にする（`PUT /notifications`）。
    /// `202` は GitHub が後から非同期に既読にするという意味で、成功として扱う。
    func markAllRead(endpoints: APIEndpoints, token: AccessToken, lastReadAt: Date) async -> ThreadActionResult {
        // 秒まで・UTC（呼び出し元は隠す範囲も秒に揃えている）
        let format = Date.ISO8601FormatStyle(includingFractionalSeconds: false, timeZone: .gmt)
        let body = MarkAllReadBody(lastReadAt: lastReadAt.formatted(format), read: true)
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
        switch await send(url, method: method, endpoints: endpoints, token: token, ifModifiedSince: nil, body: body) {
        case .success(let response): Self.classifyAction(response, success: success)
        case .failure(let failure): .failed(failure)
        }
    }

    private static func classifyAction(_ response: HTTPResponse, success: Set<Int>) -> ThreadActionResult {
        switch response.statusCode {
        case let status where success.contains(status):
            return .succeeded
        case 401:
            return .unauthorized
        case 403 where isRateLimited(response), 429:
            return .rateLimited
        default:
            return .failed(.unexpectedStatus(response.statusCode))
        }
    }

    /// リクエストを組み立てて送る。送り先がアカウントの API ベースの下でなければ送らない。
    /// `Authorization` を付けるのはこの関数だけ。
    /// `body` があるときだけ JSON のボディとして付ける（ボディはログに出さない）。
    private func send(
        _ url: URL, method: String, endpoints: APIEndpoints, token: AccessToken, ifModifiedSince: String?,
        body: Data? = nil
    ) async -> Result<HTTPResponse, FetchFailure> {
        guard endpoints.isAllowedRequestURL(url) else {
            Self.logger.error("Refused to send a request outside the API base of \(endpoints.host)")
            return .failure(.rejectedURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        // swiftlint:disable:next authorization_header_outside_client
        request.setValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if let ifModifiedSince {
            request.setValue(ifModifiedSince, forHTTPHeaderField: "If-Modified-Since")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let path = url.path()
        do {
            let response = try await transport.send(request, bodyLimit: Self.bodyLimit)
            Self.logger.info(
                "\(method) \(path) on \(endpoints.host) returned \(response.statusCode, privacy: .private)")
            if (300..<400).contains(response.statusCode) && response.statusCode != 304 {
                return .failure(.redirect)
            }
            return .success(response)
        } catch {
            Self.logger.error("\(method) \(path) on \(endpoints.host) failed: \(String(describing: error))")
            return switch error {
            case .bodyTooLarge: .failure(.bodyTooLarge)
            case .network(let code): .failure(.network(code: code))
            case .invalidResponse: .failure(.network(code: URLError.Code.badServerResponse.rawValue))
            }
        }
    }

    private func classifyFailure(_ response: HTTPResponse) -> NotificationsFetchResult {
        switch response.statusCode {
        case 401:
            return .unauthorized
        case 403, 429:
            guard let retryAt = rateLimitedUntil(response) else {
                return .forbidden(scopes: OAuthScopes(header: response.header("X-OAuth-Scopes")))
            }
            return .rateLimited(retryAt: retryAt)
        case 422:
            return .invalidRequest
        default:
            return .failed(.unexpectedStatus(response.statusCode))
        }
    }

    /// 403 / 429 のレスポンスがレート制限なら、制限が解ける時刻（`Retry-After` の秒数、`X-RateLimit-Reset`、どちらも無ければ今）。
    /// 429 は常にレート制限として扱う（ヘッダーで示されていなければ今）。レート制限でない 403 なら nil。
    private func rateLimitedUntil(_ response: HTTPResponse) -> Date? {
        guard Self.isRateLimited(response) else { return response.statusCode == 429 ? now() : nil }
        if let seconds = Self.retryAfterSeconds(response) {
            return now().addingTimeInterval(TimeInterval(max(seconds, 0)))
        }
        let reset = response.header("X-RateLimit-Reset")
            .flatMap { TimeInterval($0) }
            .map(Date.init(timeIntervalSince1970:))
        return reset ?? now()
    }

    /// 403 / 429 がレート制限を示すか（`X-RateLimit-Remaining: 0`、または `Retry-After` が秒数として読める）。
    /// 取得と操作の両方の分類で使い、判定を揃える。
    private static func isRateLimited(_ response: HTTPResponse) -> Bool {
        response.header("X-RateLimit-Remaining") == "0" || retryAfterSeconds(response) != nil
    }

    private static func retryAfterSeconds(_ response: HTTPResponse) -> Int? {
        response.header("Retry-After").flatMap { Int($0) }
    }

    private static func pollInterval(_ response: HTTPResponse) -> Int? {
        response.header("X-Poll-Interval").flatMap { Int($0) }
    }
}

/// スレッドの件名の状態とイベントの取得の結果。
enum ThreadDetailsFetchResult: Sendable, Equatable {
    case found(ThreadDetails)
    /// 番号を持たない、`404` / `410` / レート制限でない `403` / `422`（その `updated_at` の間は取り直さない）
    case unavailable
    /// 401
    case unauthorized
    /// レート制限の 403 / 429（`retryAt` まで待つ）
    case rateLimited(retryAt: Date)
    /// そのほかの状態コード、リダイレクト、通信の失敗、送らなかった、形の崩れたボディ（次の機会に取り直す）
    case failed(FetchFailure)
}

/// 状態とイベントの取得を途中で終えるときの結果（`Result` の失敗の側に載せるための入れ物）。
private struct DetailsStop: Error {
    let result: ThreadDetailsFetchResult

    init(_ result: ThreadDetailsFetchResult) {
        self.result = result
    }
}

// スレッドの件名の状態とイベントの取得（github-api「スレッドのイベントの取得のリクエスト」）
extension GitHubAPIClient {
    /// Timeline の 1 ページの件数
    private static let timelinePerPage = 100

    /// スレッドの件名の状態とイベントを取る（`GET /repos/{owner}/{repo}/issues/{number}` と、その `timeline` の
    /// 1 ページ目、最後のページ、その前のページ）。URL は `subject.url` ではなく検証済みのリポジトリ名と番号から組み立てる。
    /// 番号を持たないスレッドには何も送らない。
    func fetchDetails(
        for thread: NotificationThread, endpoints: APIEndpoints, token: AccessToken
    ) async -> ThreadDetailsFetchResult {
        guard let number = thread.subjectNumber, ThreadID.isValid(number) else { return .unavailable }
        let issuePath = "repos/\(thread.repository.owner)/\(thread.repository.name)/issues/\(number)"
        let issue: IssueSummary
        switch await get(endpoints.apiURL(path: issuePath), endpoints: endpoints, token: token) {
        case .success(let response):
            guard let decoded = IssueSummary.decode(from: response.body) else { return .failed(.malformedBody) }
            issue = decoded
        case .failure(let stop):
            return stop.result
        }
        let state = issue.subjectState

        let timeline: [TimelineItem]
        switch await fetchTimeline(
            path: issuePath + "/timeline", updatedAt: thread.updatedAt, endpoints: endpoints, token: token
        )
        {
        case .success(let items): timeline = items
        case .failure(let stop) where stop.result == .unavailable:
            return .found(ThreadDetails(state: state, event: nil))
        case .failure(let stop): return stop.result
        }
        return .found(
            ThreadDetails(
                state: state,
                event: ThreadEventResolver.event(issue: issue, timeline: timeline, updatedAt: thread.updatedAt)))
    }

    /// Timeline の 1 ページ目と、`rel="last"` があれば最後のページ、最後のページが近さの幅の始まりまで届いていなければ
    /// その前のページを取り、古い順につなげる。その前のページが 1 ページ目なら取り直さない（取るのは最大 3 ページ）。
    private func fetchTimeline(
        path: String, updatedAt: Date, endpoints: APIEndpoints, token: AccessToken
    ) async -> Result<[TimelineItem], DetailsStop> {
        guard let firstURL = Self.timelineURL(endpoints.apiURL(path: path), page: nil) else {
            return .failure(DetailsStop(.failed(.rejectedURL)))
        }
        let first = await getPage(firstURL, endpoints: endpoints, token: token)
        guard case .success(let (firstItems, link)) = first else { return first.map(\.items) }
        // `Link` からはページ番号だけを読み、URL は 1 ページ目から組み立てる（API が返した URL には送らない。
        // プロキシの下の GHES で `Link` が内部のホスト名を指していても取れるように）
        guard let lastPage = LinkHeader.lastURL(in: link).flatMap(Self.page(of:)), lastPage > 1,
            let lastURL = Self.timelineURL(firstURL, page: lastPage)
        else { return .success(firstItems) }
        let last = await getPage(lastURL, endpoints: endpoints, token: token)
        guard case .success(let (lastItems, _)) = last else { return last.map(\.items) }
        // 最後のページが近さの幅の始まりより前まで届いていれば、前のページに近い候補は無い
        guard !ThreadEventResolver.reachesBeforeWindow(lastItems, updatedAt: updatedAt) else {
            return .success(lastItems)
        }
        // その前のページが 1 ページ目なら、取ってある 1 ページ目を使う
        guard lastPage - 1 > 1 else { return .success(firstItems + lastItems) }
        guard let previousURL = Self.timelineURL(firstURL, page: lastPage - 1) else { return .success(lastItems) }
        switch await getPage(previousURL, endpoints: endpoints, token: token) {
        case .success(let previous): return .success(previous.items + lastItems)
        // 取っている間に項目が減ってページが無くなったなど。取ってある最後のページで決める
        case .failure(let stop) where stop.result == .unavailable: return .success(lastItems)
        case .failure(let stop): return .failure(stop)
        }
    }

    /// Timeline の 1 ページを取り、項目と `Link` ヘッダーを返す。
    private func getPage(
        _ url: URL, endpoints: APIEndpoints, token: AccessToken
    ) async -> Result<(items: [TimelineItem], link: String?), DetailsStop> {
        switch await get(url, endpoints: endpoints, token: token) {
        case .success(let response):
            guard let items = TimelineItem.decodePage(from: response.body) else {
                return .failure(DetailsStop(.failed(.malformedBody)))
            }
            return .success((items, response.header("Link")))
        case .failure(let result):
            return .failure(result)
        }
    }

    /// `url` の `per_page` を Timeline の件数にし、`page` があればそのページにした URL。
    private static func timelineURL(_ url: URL, page: Int?) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var items = (components.queryItems ?? []).filter { $0.name != "per_page" && $0.name != "page" }
        items.append(URLQueryItem(name: "per_page", value: String(timelinePerPage)))
        if let page { items.append(URLQueryItem(name: "page", value: String(page))) }
        components.queryItems = items
        return components.url
    }

    /// URL の `page` の値。
    private static func page(of url: URL) -> Int? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first { $0.name == "page" }?.value.flatMap { Int($0) }
    }

    /// 二次レート制限の 403 か（本文の `message` が「secondary rate limit」を含む）。本文は見分けるのにだけ使い、残さない。
    private static func isSecondaryRateLimit(_ response: HTTPResponse) -> Bool {
        struct Message: Decodable { let message: String? }
        let message = (try? JSONDecoder().decode(Message.self, from: response.body))?.message
        return message?.localizedCaseInsensitiveContains("secondary rate limit") == true
    }

    /// 状態とイベントの取得の `GET` を送り、`200` ならレスポンスを、そうでなければ結果を返す。
    private func get(
        _ url: URL, endpoints: APIEndpoints, token: AccessToken
    ) async -> Result<HTTPResponse, DetailsStop> {
        let response: HTTPResponse
        switch await send(url, method: "GET", endpoints: endpoints, token: token, ifModifiedSince: nil) {
        case .success(let value): response = value
        case .failure(let failure): return .failure(DetailsStop(.failed(failure)))
        }
        switch response.statusCode {
        case 200:
            return .success(response)
        case 401:
            return .failure(DetailsStop(.unauthorized))
        case 403, 429:
            if let retryAt = rateLimitedUntil(response) { return .failure(DetailsStop(.rateLimited(retryAt: retryAt))) }
            // 待ち時間のヘッダーが無い二次レート制限は、本文で見分けて止める（待つ時間は呼び出し元の最短の時間）
            if Self.isSecondaryRateLimit(response) { return .failure(DetailsStop(.rateLimited(retryAt: now()))) }
            return .failure(DetailsStop(.unavailable))
        case 404, 410, 422:
            return .failure(DetailsStop(.unavailable))
        default:
            return .failure(DetailsStop(.failed(.unexpectedStatus(response.statusCode))))
        }
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
