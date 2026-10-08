import Foundation
import Synchronization

/// `Process` で子プロセスを起動する `ProcessRunning`。
///
/// 標準出力と標準エラー出力は読みながら上限と比べる（終了を待ってからまとめて読むと、パイプが詰まって止まるため）。
/// タイムアウトや出力の超過では SIGTERM を送り、1 秒たっても終わらなければ SIGKILL を送る。
struct SubprocessRunner: ProcessRunning {
    func run(_ request: ProcessRequest) async throws -> ProcessOutput {
        let process = Process()
        process.executableURL = request.executable
        process.arguments = request.arguments
        process.environment = request.environment
        process.standardInput = FileHandle.nullDevice
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let state = RunState(stdoutLimit: request.stdoutLimit, stderrLimit: request.stderrLimit)
        Self.read(stdoutPipe, onData: state.appendStdout, onClose: state.closeStdout)
        Self.read(stderrPipe, onData: state.appendStderr, onClose: state.closeStderr)
        // 終了するまで Process を保持しておく（タイムアウトで先に戻っても、終了の通知を受け取れるように）
        let retained = ProcessBox(process)
        process.terminationHandler = { finished in
            state.exited(status: finished.terminationStatus)
            retained.release()
        }

        let timeoutTask = Task {
            try? await Task.sleep(for: request.timeout)
            if !Task.isCancelled {
                state.fail(ProcessRunError.timedOut)
            }
        }
        defer { timeoutTask.cancel() }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.start(continuation)
                do {
                    try process.run()
                    state.launched(pid: process.processIdentifier)
                } catch {
                    retained.release()
                    state.fail(ProcessRunError.launchFailed)
                }
            }
        } onCancel: {
            state.fail(CancellationError())
        }
    }
}

extension SubprocessRunner {
    /// パイプを読みながら `onData` に渡し、閉じたら `onClose` を呼ぶ。
    fileprivate static func read(
        _ pipe: Pipe, onData: @escaping @Sendable (Data) -> Void, onClose: @escaping @Sendable () -> Void
    ) {
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                onClose()
            } else {
                onData(data)
            }
        }
    }
}

/// `terminationHandler` から参照するために Process を包む。中身は終了後に手放す。
private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?

    init(_ process: Process) {
        self.process = process
    }

    func release() {
        lock.withLock { process = nil }
    }
}

/// パイプと終了の通知（どちらも任意のスレッドで届く）を集め、結果を 1 回だけ返す。
private final class RunState: Sendable {
    private struct Inner {
        var stdout = Data()
        var stderr = Data()
        var stdoutClosed = false
        var stderrClosed = false
        var exitStatus: Int32?
        var pid: pid_t = 0
        var continuation: CheckedContinuation<ProcessOutput, any Error>?
        var finished = false
    }

    private let inner = Mutex(Inner())
    private let stdoutLimit: Int
    private let stderrLimit: Int

    init(stdoutLimit: Int, stderrLimit: Int) {
        self.stdoutLimit = stdoutLimit
        self.stderrLimit = stderrLimit
    }

    func start(_ continuation: CheckedContinuation<ProcessOutput, any Error>) {
        let alreadyFinished = inner.withLock { inner in
            if inner.finished { return true }
            inner.continuation = continuation
            return false
        }
        // キャンセルが先に届いていたら、すぐに返す
        if alreadyFinished {
            continuation.resume(throwing: CancellationError())
        }
    }

    func launched(pid: pid_t) {
        let shouldTerminate = inner.withLock { inner in
            inner.pid = pid
            return inner.finished && inner.exitStatus == nil
        }
        if shouldTerminate {
            terminate()
        }
    }

    func appendStdout(_ data: Data) {
        let overflowed = inner.withLock { inner in
            guard !inner.finished else { return false }
            inner.stdout.append(data)
            return inner.stdout.count > stdoutLimit
        }
        if overflowed {
            fail(ProcessRunError.outputTooLarge)
        }
    }

    func appendStderr(_ data: Data) {
        inner.withLock { inner in
            let room = stderrLimit - inner.stderr.count
            if room > 0 {
                inner.stderr.append(data.prefix(room))
            }
        }
    }

    func closeStdout() {
        finishIfComplete { $0.stdoutClosed = true }
    }

    func closeStderr() {
        finishIfComplete { $0.stderrClosed = true }
    }

    func exited(status: Int32) {
        finishIfComplete { $0.exitStatus = status }
    }

    /// 失敗として結果を返し、子プロセスがまだ動いていれば終了させる。
    func fail(_ error: any Error) {
        let continuation = inner.withLock { inner -> CheckedContinuation<ProcessOutput, any Error>? in
            if inner.finished { return nil }
            inner.finished = true
            defer { inner.continuation = nil }
            return inner.continuation
        }
        continuation?.resume(throwing: error)
        terminate()
    }

    private func finishIfComplete(_ update: (inout Inner) -> Void) {
        let result = inner.withLock { inner -> (CheckedContinuation<ProcessOutput, any Error>, ProcessOutput)? in
            update(&inner)
            guard !inner.finished, inner.stdoutClosed, inner.stderrClosed, let status = inner.exitStatus,
                let continuation = inner.continuation
            else { return nil }
            inner.finished = true
            inner.continuation = nil
            return (continuation, ProcessOutput(exitCode: status, stdout: inner.stdout, stderr: inner.stderr))
        }
        if let (continuation, output) = result {
            continuation.resume(returning: output)
        }
    }

    private func terminate() {
        guard let pid = runningPID() else { return }
        kill(pid, SIGTERM)
        Task {
            try? await Task.sleep(for: .seconds(1))
            if let pid = self.runningPID() {
                kill(pid, SIGKILL)
            }
        }
    }

    /// まだ終了していない子プロセスの PID。起動前（PID が 0）や終了後は nil（別のプロセスにシグナルを送らないため）。
    private func runningPID() -> pid_t? {
        inner.withLock { inner in
            inner.pid > 0 && inner.exitStatus == nil ? inner.pid : nil
        }
    }
}
