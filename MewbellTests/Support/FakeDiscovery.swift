import Synchronization

@testable import Mewbell

/// `gh auth token` を、開くまで待たせる `ProcessRunning`。
final class GatedProcessRunner: ProcessRunning {
    private let base: FakeProcessRunner
    private let gate = Mutex<(isOpen: Bool, waiters: [CheckedContinuation<Void, Never>])>((true, []))

    init(base: FakeProcessRunner) {
        self.base = base
    }

    var waitingCount: Int { gate.withLock { $0.waiters.count } }

    func close() {
        gate.withLock { $0.isOpen = false }
    }

    func open() {
        let waiters = gate.withLock { gate in
            gate.isOpen = true
            defer { gate.waiters = [] }
            return gate.waiters
        }
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitUntilWaiting(_ count: Int) async {
        await waitUntil { self.waitingCount >= count }
    }

    func run(_ request: ProcessRequest) async throws -> ProcessOutput {
        if request.arguments.first == "auth" {
            await withCheckedContinuation { continuation in
                let passes = gate.withLock { gate in
                    if gate.isOpen { return true }
                    gate.waiters.append(continuation)
                    return false
                }
                if passes { continuation.resume() }
            }
        }
        // 待っている間に取得がキャンセルされていたら、gh が止められたものとして失敗させる
        try Task.checkCancellation()
        return try await base.run(request)
    }
}

/// 読み込みが呼ばれた回数を数え、`finish()` まで終わらない `AccountDiscovering`。
final class BlockingDiscovery: AccountDiscovering {
    private let calls = Mutex(0)
    /// `finish()` された回数（読み込みを 1 回ずつ進める許可）と、許可を待っている読み込み
    private let gate = Mutex<(permits: Int, waiters: [CheckedContinuation<Void, Never>])>((0, []))
    private let recordedEvents = Mutex<[String]>([])
    private let recordedOptions = Mutex<[DiscoveryOptions]>([])
    private let resultState = Mutex<DiscoveryState>(.notLoggedIn)

    /// 読み込みの最後に渡す状態
    var result: DiscoveryState {
        get { resultState.withLock { $0 } }
        set { resultState.withLock { $0 = newValue } }
    }
    /// 読み込みに渡された設定
    var options: [DiscoveryOptions] { recordedOptions.withLock { $0 } }

    var callCount: Int { calls.withLock { $0 } }
    /// 読み込みの終了と破棄が起きた順
    var events: [String] { recordedEvents.withLock { $0 } }

    func reload(
        userInitiated: Bool, options: DiscoveryOptions, update: @escaping @Sendable (DiscoveryState) async -> Void
    ) async {
        calls.withLock { $0 += 1 }
        recordedOptions.withLock { $0.append(options) }
        recordedEvents.withLock { $0.append(userInitiated ? "reload(user)" : "reload") }
        await withCheckedContinuation { continuation in
            let resumeNow = gate.withLock { gate in
                if gate.permits > 0 {
                    gate.permits -= 1
                    return true
                }
                gate.waiters.append(continuation)
                return false
            }
            if resumeNow {
                continuation.resume()
            }
        }
        await update(result)
        recordedEvents.withLock { $0.append("reloadFinished") }
    }

    func disable(_ id: AccountID) async {
        recordedEvents.withLock { $0.append("disable \(id)") }
    }

    func enable(_ id: AccountID) async {
        recordedEvents.withLock { $0.append("enable \(id)") }
    }

    func discardAllTokens() async {
        recordedEvents.withLock { $0.append("discardAll") }
    }

    func closeCredentials() async {
        recordedEvents.withLock { $0.append("closed") }
    }

    /// 待っている読み込みを 1 つ進める（待っていなければ、次の読み込みをすぐ通す）。
    func finish() {
        let waiter = gate.withLock { gate -> CheckedContinuation<Void, Never>? in
            if gate.waiters.isEmpty {
                gate.permits += 1
                return nil
            }
            return gate.waiters.removeFirst()
        }
        waiter?.resume()
    }
}
