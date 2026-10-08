import Foundation

/// HTTP のレスポンス。ヘッダー名は大文字小文字を区別せずに引く。
struct HTTPResponse: Sendable {
    let statusCode: Int
    let body: Data
    private let headers: [String: String]

    init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.body = body
        self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { $1 })
    }

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

enum TransportError: Error, Equatable, Sendable {
    /// ボディが上限を超えた
    case bodyTooLarge
    /// 通信の失敗・タイムアウト（`URLError` のコードだけを持つ）
    case network(code: Int)
    case invalidResponse
}

/// リクエストを送ってレスポンスを返す。テストでは偽物に差し替える。
protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest, bodyLimit: Int) async throws(TransportError) -> HTTPResponse
}

/// `URLSession` を使うトランスポート。キャッシュ・Cookie・資格情報の保存を使わず、リダイレクトをたどらない。
final class URLSessionTransport: HTTPTransport {
    let session: URLSession

    init() {
        session = URLSession(
            configuration: Self.makeConfiguration(), delegate: RedirectRejectingDelegate(), delegateQueue: nil)
    }

    deinit {
        session.invalidateAndCancel()
    }

    /// 共有の設定にトークンを入れない（`httpAdditionalHeaders` は空のまま）。
    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        configuration.httpAdditionalHeaders = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        return configuration
    }

    func send(_ request: URLRequest, bodyLimit: Int) async throws(TransportError) -> HTTPResponse {
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else {
                bytes.task.cancel()
                throw TransportError.invalidResponse
            }
            if response.expectedContentLength > Int64(bodyLimit) {
                bytes.task.cancel()
                throw TransportError.bodyTooLarge
            }
            var body = Data()
            for try await byte in bytes {
                guard body.count < bodyLimit else {
                    bytes.task.cancel()
                    throw TransportError.bodyTooLarge
                }
                body.append(byte)
            }
            var headers: [String: String] = [:]
            for case (let name as String, let value as String) in response.allHeaderFields {
                headers[name] = value
            }
            return HTTPResponse(statusCode: response.statusCode, headers: headers, body: body)
        } catch let error as TransportError {
            throw error
        } catch let error as URLError {
            throw .network(code: error.code.rawValue)
        } catch {
            throw .network(code: URLError.Code.unknown.rawValue)
        }
    }
}

/// リダイレクトをすべて拒否する。3xx のレスポンスはそのまま呼び出し元に返る。
final class RedirectRejectingDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        // async 版は Swift 6.4 のコンパイラが ObjC のサンクを作るところで落ちるので、completion handler 版を使う
        completionHandler(nil)
    }
}
