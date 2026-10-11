import Foundation

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
struct DetailsStop: Error {
    let result: ThreadDetailsFetchResult

    init(_ result: ThreadDetailsFetchResult) {
        self.result = result
    }
}

// スレッドの件名の状態とイベントの取得（github-api「スレッドのイベントの取得のリクエスト」）
extension GitHubAPIClient {
    /// Timeline の 1 ページの件数
    static let timelinePerPage = 100

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
            path: issuePath + "/timeline", issue: issue, updatedAt: thread.updatedAt, endpoints: endpoints, token: token
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

    /// Timeline の 1 ページ目と、`rel="last"` があれば最後のページ、そこに候補が無ければその前のページを取り、古い順につなげる。
    /// その前のページが 1 ページ目なら取り直さない（取るのは最大 3 ページ）。
    private func fetchTimeline(
        path: String, issue: IssueSummary, updatedAt: Date, endpoints: APIEndpoints, token: AccessToken
    ) async -> Result<[TimelineItem], DetailsStop> {
        guard let firstURL = Self.timelineURL(endpoints.apiURL(path: path), page: nil) else {
            return .failure(DetailsStop(.failed(.rejectedURL)))
        }
        let first = await getPage(firstURL, endpoints: endpoints, token: token)
        guard case .success(let (firstItems, link)) = first else { return first.map(\.items) }
        guard let lastURL = LinkHeader.lastURL(in: link), let lastPage = Self.page(of: lastURL), lastPage > 1 else {
            return .success(firstItems)
        }
        // 最後のページの URL は API が返したものなので、`send` のオリジン検査を通るものだけに送る
        let last = await getPage(lastURL, endpoints: endpoints, token: token)
        guard case .success(let (lastItems, _)) = last else { return last.map(\.items) }
        guard lastPage - 1 > 1, let createdAt = ThreadEventResolver.date(issue.createdAt),
            ThreadEventResolver.closestCandidate(in: lastItems, createdAt: createdAt, updatedAt: updatedAt) == nil,
            let previousURL = Self.timelineURL(firstURL, page: lastPage - 1)
        else { return .success(lastItems) }
        return await getPage(previousURL, endpoints: endpoints, token: token).map { $0.items + lastItems }
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
            return .failure(DetailsStop(.unavailable))
        case 404, 410, 422:
            return .failure(DetailsStop(.unavailable))
        default:
            return .failure(DetailsStop(.failed(.unexpectedStatus(response.statusCode))))
        }
    }
}
