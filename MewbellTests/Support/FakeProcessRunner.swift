import Foundation
import Synchronization

@testable import Mewbell

/// 受け取った起動内容を記録し、用意した結果を返す `ProcessRunning`。
final class FakeProcessRunner: ProcessRunning {
    typealias Handler = @Sendable (ProcessRequest) throws -> ProcessOutput

    private let handler: Handler
    private let recorded = Mutex<[ProcessRequest]>([])

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    var requests: [ProcessRequest] { recorded.withLock { $0 } }

    func run(_ request: ProcessRequest) async throws -> ProcessOutput {
        recorded.withLock { $0.append(request) }
        return try handler(request)
    }

    static func output(_ stdout: String, exitCode: Int32 = 0, stderr: String = "") -> ProcessOutput {
        ProcessOutput(exitCode: exitCode, stdout: Data(stdout.utf8), stderr: Data(stderr.utf8))
    }
}

/// テスト用の一時ディレクトリ。破棄するときに中身ごと消す。
final class TemporaryDirectory: Sendable {
    let url = FileManager.default.temporaryDirectory.appending(path: "MewbellTests-\(UUID().uuidString)")

    init() throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// 内容とパーミッションを指定してファイルを作り、パスを返す。
    @discardableResult
    func makeFile(_ name: String, contents: String = "#!/bin/sh\n", permissions: Int16 = 0o755) throws -> String {
        let file = url.appending(path: name)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: file.path)
        return file.path
    }
}

/// クロージャーから共有できる、ロック付きの値。
final class LockedValue<Value: Sendable>: Sendable {
    private let mutex: Mutex<Value>

    init(_ value: Value) {
        mutex = Mutex(value)
    }

    var value: Value {
        get { mutex.withLock { $0 } }
        set { mutex.withLock { $0 = newValue } }
    }
}
