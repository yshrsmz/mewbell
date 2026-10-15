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
    /// 条件に合うリクエストの応答を、nil に戻すまで止める（`pausedMethod` と同じく async で待つ）
    let pausedWhere = LockedValue<(@Sendable (URLRequest) -> Bool)?>(nil)

    func setHandler(_ handler: @escaping Handler) {
        self.handler.value = handler
    }

    func send(_ request: URLRequest, bodyLimit: Int) async throws(TransportError) -> HTTPResponse {
        recorded.withLock { $0.append(request) }
        while pausedMethod.value == request.httpMethod || pausedWhere.value?(request) == true {
            // 打ち切られたリクエスト（タスクグループの取り消しなど）は、本物と同じく通信の失敗で終える
            guard !Task.isCancelled else { throw .network(code: URLError.Code.cancelled.rawValue) }
            try? await Task.sleep(for: .milliseconds(5))
        }
        let handler = handler.value
        return try handler(request)
    }

    /// 待ち時間のヘッダーが無い二次レート制限の 403（本文の `message` で見分ける）。
    static func secondaryRateLimit(headers: [String: String] = [:]) -> HTTPResponse {
        HTTPResponse(
            statusCode: 403, headers: headers,
            body: Data(#"{"message": "You have exceeded a secondary rate limit. Please wait a few minutes."}"#.utf8))
    }

    /// 通知のスレッドの JSON（1 件）。
    /// `subjectURL` を渡すと、そのスレッドは番号を持つ（状態とイベントを取る対象になる）。
    static func threadJSON(
        id: String, repository: String = "octo/app", updatedAt: String = "2026-10-08T12:00:00Z",
        subjectURL: String? = nil, type: String = "Issue", title: String? = nil
    ) -> String {
        """
        {"id": "\(id)", "unread": true, "reason": "subscribed", "updated_at": "\(updatedAt)",
         "repository": {"full_name": "\(repository)"},
         "subject": {"title": "\(title ?? "Thread \(id)")", "url": \(subjectURL.map { "\"\($0)\"" } ?? "null"), "type": "\(type)"}}
        """
    }

    static func page(_ ids: some Sequence<Int>, repository: String = "octo/app") -> Data {
        Data("[\(ids.map { threadJSON(id: String($0), repository: repository) }.joined(separator: ","))]".utf8)
    }
}

extension FakeHTTPTransport {
    /// 届いた `GET` の `If-Modified-Since`（順に）。既読・Done などの `GET` 以外は含めない
    var ifModifiedSince: [String?] {
        requests.filter { $0.httpMethod == "GET" }.map { $0.value(forHTTPHeaderField: "If-Modified-Since") }
    }
}
