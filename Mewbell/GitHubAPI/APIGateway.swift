import Foundation
import os

/// トークンを `Authorization` に付けて送る関所。送るのは `send` だけで、送り先がアカウントの API ベースの下でなければ送らない。
/// 状態を持たない。`GitHubAPIClient` が持ち、呼び出し元の actor の上で動く。
struct APIGateway: Sendable {
    private static let bodyLimit = 5 * 1024 * 1024
    private static let logger = Logger(category: "GitHubAPI")
    private static let userAgent = "Mewbell/\(AppInfo.version)"

    /// 送るのは `send` だけ（オリジン検査とリダイレクトの扱いを迂回させないため、外に見せない）
    private let transport: any HTTPTransport

    init(transport: any HTTPTransport) {
        self.transport = transport
    }

    /// リクエストを組み立てて送る。送り先がアカウントの API ベースの下でなければ送らない。
    /// `Authorization` を付けるのはこの関数だけ。
    /// `body` があるときだけ JSON のボディとして付ける（ボディはログに出さない）。
    func send(
        _ url: URL, method: String, endpoints: APIEndpoints, token: AccessToken, ifModifiedSince: String?,
        body: Data? = nil
    ) async -> Result<HTTPResponse, FetchFailure> {
        guard endpoints.isAllowedRequestURL(url) else {
            Self.logger.error("Refused to send a request outside the API base of \(endpoints.host)")
            return .failure(.rejectedURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        // swiftlint:disable:next authorization_header_outside_gateway
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
}
