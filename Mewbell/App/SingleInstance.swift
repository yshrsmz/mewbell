import Foundation

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

    /// ロックを取れたら `true`。ほかのプロセス（または別の `SingleInstanceLock`）が持っていれば `false`。
    func tryAcquire() -> Bool {
        guard fileDescriptor < 0 else { return true }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(fileURL.path, O_RDWR | O_CREAT | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return false }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return false
        }
        fileDescriptor = descriptor
        return true
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

    /// ロックを取れなければ、ほかの Mewbell が動いているのでこのプロセスを終了する。
    /// テストのホストとして起動されたときはロックを取らない（起動中の Mewbell があってもテストを走らせられるように、
    /// また、テスト中に普段使いの Mewbell を起動しても終了しないように）。
    @MainActor
    static func terminateIfAnotherInstanceIsRunning() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
            let bundleIdentifier = Bundle.main.bundleIdentifier,
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first
        else { return }

        let lockURL = applicationSupport.appending(path: bundleIdentifier).appending(path: "instance.lock")
        let lock = SingleInstanceLock(fileURL: lockURL)
        guard lock.tryAcquire() else { exit(EXIT_SUCCESS) }
        self.lock = lock
    }
}
