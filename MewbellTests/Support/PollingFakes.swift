import Foundation
import Synchronization
import Testing

@testable import Mewbell

/// 要求された待ち時間を記録し、`advance()` されるまで止まる `sleep`。キャンセルされたら `CancellationError` を投げる。
final class ManualSleeper: Sendable {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let state = Mutex<(durations: [Duration], waiters: [Waiter])>(([], []))

    var durations: [Duration] { state.withLock { $0.durations } }

    var sleep: AccountPoller.Sleep {
        { duration in try await self.wait(duration) }
    }

    private func wait(_ duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.withLock {
                    $0.durations.append(duration)
                    $0.waiters.append(Waiter(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            let waiter = state.withLock { state -> Waiter? in
                guard let index = state.waiters.firstIndex(where: { $0.id == id }) else { return nil }
                return state.waiters.remove(at: index)
            }
            waiter?.continuation.resume(throwing: CancellationError())
        }
    }

    /// 最も古い待ちを 1 つ進める。
    func advance() {
        let waiter = state.withLock { $0.waiters.isEmpty ? nil : $0.waiters.removeFirst() }
        waiter?.continuation.resume()
    }

    /// `count` 回目の待ちが始まるまで待つ。
    func waitForSleeps(_ count: Int) async {
        await waitUntil { self.durations.count >= count }
    }
}

/// 条件が満たされるまで待つ（2 秒で諦める）。
func waitUntil(_ condition: @Sendable () -> Bool) async {
    let deadline = ContinuousClock.now + .seconds(2)
    while !condition() && ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(1))
    }
}

/// トークンの受け渡しを記録する `TokenProviding`。
final class FakeTokenProvider: TokenProviding {
    private let tokens = LockedValue<[AccountID: AccessToken]>([:])
    /// 取り直しで返すトークンの値（nil なら取り直せない）
    let refreshedValue = LockedValue<String?>(nil)
    let refreshCount = LockedValue(0)
    let discardCount = LockedValue(0)

    init(_ initial: [AccountID: String] = [:]) {
        for (id, value) in initial {
            set(value, for: id)
        }
    }

    func set(_ value: String, for id: AccountID) {
        tokens.withLock { $0[id] = AccessToken(ghOutput: Data(value.utf8)) }
    }

    func currentToken(for id: AccountID) async -> AccessToken? {
        tokens.value[id]
    }

    func refreshToken(for id: AccountID) async -> AccessToken? {
        refreshCount.withLock { $0 += 1 }
        let token = refreshedValue.value.flatMap { AccessToken(ghOutput: Data($0.utf8)) }
        tokens.withLock { $0[id] = token }
        return token
    }

    func discardToken(for id: AccountID) async {
        discardCount.withLock { $0 += 1 }
        tokens.withLock { $0[id] = nil }
    }
}

/// `AccountPoller` を偽のトランスポート・トークン・時計で動かす。
final class PollerFixture: Sendable {
    static let alice = AccountID(host: "github.com", user: "alice")
    static let now = Date(timeIntervalSince1970: 1_791_460_800)

    let transport = FakeHTTPTransport()
    let tokens = FakeTokenProvider([alice: "test-token-alice"])
    let sleeper = ManualSleeper()
    let updates = LockedValue<[FeedState]>([])
    /// ポーラーが見る時刻。テストで進められる
    let clock = LockedValue(now)
    let poller: AccountPoller

    init() throws {
        let updates = updates
        let clock = clock
        poller = AccountPoller(
            accountID: Self.alice, endpoints: try #require(APIEndpoints(host: "github.com")),
            client: GitHubAPIClient(transport: transport, now: { clock.value }), tokens: tokens,
            sleep: sleeper.sleep, now: { clock.value }, onUpdate: { state in updates.withLock { $0.append(state) } })
    }

    /// 時刻だけを進める（待っているポーラーは起こさない）。
    func moveClock(by seconds: TimeInterval) {
        clock.withLock { $0 = $0.addingTimeInterval(seconds) }
    }

    /// 時刻を進めてから、待っているポーラーを次の取得に進める。
    func advance(by seconds: TimeInterval) {
        moveClock(by: seconds)
        sleeper.advance()
    }

    var last: FeedState? { updates.value.last }

    func respond(_ responses: [HTTPResponse]) {
        let queue = LockedValue(responses)
        transport.setHandler { _ throws(TransportError) in
            guard let next = queue.withLock({ $0.isEmpty ? nil : $0.removeFirst() }) else {
                throw .network(code: URLError.Code.notConnectedToInternet.rawValue)
            }
            return next
        }
    }

    /// `GET` には `gets` を順に返し（尽きたら通信の失敗）、ほかのメソッドには `other` の結果を返す。
    func respond(gets: [HTTPResponse], other: @escaping FakeHTTPTransport.Handler) {
        let queue = LockedValue(gets)
        transport.setHandler { request throws(TransportError) in
            if request.httpMethod != "GET" {
                return try other(request)
            }
            guard let next = queue.withLock({ $0.isEmpty ? nil : $0.removeFirst() }) else {
                throw .network(code: URLError.Code.notConnectedToInternet.rawValue)
            }
            return next
        }
    }

    static func ok(_ ids: ClosedRange<Int>, lastModified: String = "LM-1", scopes: String = "repo") -> HTTPResponse {
        ok(body: FakeHTTPTransport.page(ids), lastModified: lastModified, scopes: scopes)
    }

    static func ok(body: Data, lastModified: String = "LM-1", scopes: String = "repo") -> HTTPResponse {
        HTTPResponse(
            statusCode: 200,
            headers: ["Last-Modified": lastModified, "X-OAuth-Scopes": scopes, "X-Poll-Interval": "60"],
            body: body)
    }

    static let notModified = HTTPResponse(statusCode: 304)

    var ifModifiedSince: [String?] { transport.ifModifiedSince }

    var authorizations: [String?] {
        transport.requests.map { $0.value(forHTTPHeaderField: "Authorization") }
    }

    func requests(_ method: String) -> [URLRequest] {
        transport.requests.filter { $0.httpMethod == method }
    }

    /// 最後に届いた一覧のスレッドの ID
    var lastIDs: [String] { last?.threads.map(\.id) ?? [] }
}
