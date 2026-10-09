import Foundation

@testable import Mewbell

/// 受け取ったリクエストを記録し、用意した応答を返す `HTTPTransport`。
final class FakeHTTPTransport: HTTPTransport {
    typealias Handler = @Sendable (URLRequest) throws(TransportError) -> HTTPResponse

    private let handler: LockedValue<Handler>
    private let recorded = LockedValue<[URLRequest]>([])

    init(handler: @escaping Handler = { _ in HTTPResponse(statusCode: 200, body: Data("[]".utf8)) }) {
        self.handler = LockedValue(handler)
    }

    var requests: [URLRequest] { recorded.value }

    /// この HTTP メソッドのリクエストの応答を、nil に戻すまで止める（スレッドを塞がずに待つので、呼び出し元の actor に入れる）
    let pausedMethod = LockedValue<String?>(nil)

    func setHandler(_ handler: @escaping Handler) {
        self.handler.value = handler
    }

    func send(_ request: URLRequest, bodyLimit: Int) async throws(TransportError) -> HTTPResponse {
        recorded.withLock { $0.append(request) }
        while let method = pausedMethod.value, method == request.httpMethod {
            try? await Task.sleep(for: .milliseconds(5))
        }
        let handler = handler.value
        let response = try handler(request)
        guard response.body.count <= bodyLimit else { throw .bodyTooLarge }
        return response
    }

    /// 通知のスレッドの JSON（1 件）。
    static func threadJSON(id: String, repository: String = "octo/app", updatedAt: String = "2026-10-08T12:00:00Z")
        -> String
    {
        """
        {"id": "\(id)", "unread": true, "reason": "subscribed", "updated_at": "\(updatedAt)",
         "repository": {"full_name": "\(repository)"},
         "subject": {"title": "Thread \(id)", "url": null, "type": "Issue"}}
        """
    }

    static func page(_ ids: some Sequence<Int>, repository: String = "octo/app") -> Data {
        Data("[\(ids.map { threadJSON(id: String($0), repository: repository) }.joined(separator: ","))]".utf8)
    }
}
