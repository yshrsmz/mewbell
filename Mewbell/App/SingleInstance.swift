import Foundation
import os

/// ファイルロック（flock）で、Mewbell がユーザーごとに 1 つだけ動くようにする。
///
/// ロックは OS がまとめて取得するので、同時に起動しても片方しか取れない。
/// プロセスが終了すればロックは自動で外れるため、ロックファイルの後片付けは要らない。
final class SingleInstanceLock {
    private let fileURL: URL
    private var fileDescriptor: Int32 = -1

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    deinit {
        release()
    }

    enum AcquireResult: Equatable {
        /// ロックを取れた
        case acquired
        /// ほかのプロセス（または別の `SingleInstanceLock`）がロックを持っている
        case heldByAnotherInstance
        /// ロックファイルを開けない・ロックを取れないなどのエラー（`errno` を持つ）
        case failed(errno: Int32)
    }

    func tryAcquire() -> AcquireResult {
        guard fileDescriptor < 0 else { return .acquired }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(fileURL.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return .failed(errno: errno) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let error = errno
            close(descriptor)
            return error == EWOULDBLOCK ? .heldByAnotherInstance : .failed(errno: error)
        }
        fileDescriptor = descriptor
        return .acquired
    }

    func release() {
        guard fileDescriptor >= 0 else { return }
        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
        fileDescriptor = -1
    }
}

enum SingleInstance {
    /// プロセスが終わるまでロックを持ち続けるために保持しておく。
    @MainActor private static var lock: SingleInstanceLock?

    private static let logger = Logger(subsystem: "com.codingfeline.mewbell", category: "SingleInstance")

    /// ほかの Mewbell がロックを持っていれば、このプロセスを終了する。
    /// ロックファイルを開けないなどのエラーでは終了せず、記録したうえで起動を続ける
    /// （誤って起動できなくなるよりは、二重起動を防げない方が被害が小さい）。
    /// テストのホストや SwiftUI プレビューとして起動されたときはロックを取らない（起動中の Mewbell があっても
    /// テストやプレビューを動かせるように、また、その間に普段使いの Mewbell を起動しても終了しないように）。
    /// すでにロックを持っていれば何もしない（同じプロセスで取り直すと、自分のロックに阻まれて終了してしまうため）。
    @MainActor
    static func terminateIfAnotherInstanceIsRunning() {
        guard lock == nil else { return }
        let environment = ProcessInfo.processInfo.environment
        guard environment["XCTestConfigurationFilePath"] == nil,
            environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1"
        else { return }
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            logger.error("Could not lock: no bundle identifier")
            return
        }
        guard
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first
        else {
            logger.error("Could not lock: no Application Support directory")
            return
        }

        let lockURL = applicationSupport.appending(path: bundleIdentifier).appending(path: "instance.lock")
        let lock = SingleInstanceLock(fileURL: lockURL)
        switch lock.tryAcquire() {
        case .acquired:
            self.lock = lock
        case .heldByAnotherInstance:
            exit(EXIT_SUCCESS)
        case .failed(let error):
            logger.error("Could not lock \(lockURL.path): errno \(error)")
        }
    }
}
