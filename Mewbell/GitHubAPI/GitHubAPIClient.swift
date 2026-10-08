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
}

enum NotificationsFetchResult: Sendable, Equatable {
    case updated(threads: [NotificationThread], lastModified: String?, pollInterval: Int?, scopes: OAuthScopes)
    case notModified(pollInterval: Int?)
    /// 401
    case unauthorized
    /// レート制限の 403（`retryAt` まで待つ）
    case rateLimited(retryAt: Date)
    /// レート制限でない 403
    case forbidden
    /// 422
    case invalidRequest
    case failed(FetchFailure)
}

/// GitHub の REST API のクライアント。トークンを `Authorization` に付けるのはこの型だけ。
/// 状態を持たない。`AccountPoller` の中から呼ぶ。
struct GitHubAPIClient: Sendable {
    static let pageLimit = 10
    static let bodyLimit = 5 * 1024 * 1024
    private static let logger = Logger(category: "GitHubAPI")
    private static let userAgent =
        "Mewbell/\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")"

    let transport: any HTTPTransport
    /// `X-RateLimit-Reset` から待ち時間を出すための現在時刻
    var now: @Sendable () -> Date = { Date() }

    /// 未読の通知を、`rel="next"` をたどって取得する。すべてのページに同じ `token` を付ける。
    func fetchNotifications(
        endpoints: APIEndpoints, token: AccessToken, ifModifiedSince: String?, participating: Bool = false
    ) async -> NotificationsFetchResult {
        var components = URLComponents(
            url: endpoints.apiURL(path: "notifications"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "all", value: "false"),
            URLQueryItem(name: "participating", value: participating ? "true" : "false"),
            URLQueryItem(name: "per_page", value: "50"),
        ]
        guard var url = components?.url else { return .failed(.rejectedURL) }

        var threads: [NotificationThread] = []
        var firstResponse: HTTPResponse?
        var page = 1
        while true {
            let response: HTTPResponse
            switch await send(
                url, endpoints: endpoints, token: token, ifModifiedSince: page == 1 ? ifModifiedSince : nil)
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
            guard let pageThreads = NotificationThread.decodeList(from: response.body) else {
                Self.logger.error("Could not decode notifications page \(page)")
                return .failed(.malformedBody)
            }
            threads += pageThreads
            let first = firstResponse ?? response
            firstResponse = first
            guard page < Self.pageLimit, let next = LinkHeader.nextURL(in: response.header("Link")) else {
                // 続きが無いか、ページの上限まで取った（それ以上は取らず、取った分で一覧を作る）
                return .updated(
                    threads: threads, lastModified: first.header("Last-Modified"),
                    pollInterval: Self.pollInterval(first), scopes: OAuthScopes(header: first.header("X-OAuth-Scopes")))
            }
            url = next
            page += 1
        }
    }

    /// リクエストを組み立てて送る。送り先がアカウントの API ベースの下でなければ送らない。
    private func send(
        _ url: URL, endpoints: APIEndpoints, token: AccessToken, ifModifiedSince: String?
    ) async -> Result<HTTPResponse, FetchFailure> {
        guard endpoints.isAllowedRequestURL(url) else {
            Self.logger.error("Refused to send a request outside the API base of \(endpoints.host)")
            return .failure(.rejectedURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if let ifModifiedSince {
            request.setValue(ifModifiedSince, forHTTPHeaderField: "If-Modified-Since")
        }
        let path = url.path()
        do {
            let response = try await transport.send(request, bodyLimit: Self.bodyLimit)
            Self.logger.info("GET \(path) on \(endpoints.host) returned \(response.statusCode)")
            if (300..<400).contains(response.statusCode) && response.statusCode != 304 {
                return .failure(.redirect)
            }
            return .success(response)
        } catch {
            Self.logger.error("GET \(path) on \(endpoints.host) failed: \(String(describing: error))")
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
        case 403:
            if let seconds = response.header("Retry-After").flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }) {
                return .rateLimited(retryAt: now().addingTimeInterval(TimeInterval(max(seconds, 0))))
            }
            if response.header("X-RateLimit-Remaining")?.trimmingCharacters(in: .whitespaces) == "0" {
                let reset = response.header("X-RateLimit-Reset")
                    .flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) }
                    .map(Date.init(timeIntervalSince1970:))
                return .rateLimited(retryAt: reset ?? now())
            }
            return .forbidden
        case 422:
            return .invalidRequest
        default:
            return .failed(.unexpectedStatus(response.statusCode))
        }
    }

    private static func pollInterval(_ response: HTTPResponse) -> Int? {
        response.header("X-Poll-Interval").flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }
}
