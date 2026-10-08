import Foundation
import Synchronization

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
