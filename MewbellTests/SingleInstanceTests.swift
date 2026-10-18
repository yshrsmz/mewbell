import Foundation
import Testing

@testable import Mewbell

final class SingleInstanceLockTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "MewbellTests-\(UUID().uuidString)")
    private var lockURL: URL { directory.appending(path: "instance.lock") }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func secondInstanceCannotAcquireWhileFirstHoldsTheLock() {
        let first = SingleInstanceLock(fileURL: lockURL)
        let second = SingleInstanceLock(fileURL: lockURL)
        #expect(first.tryAcquire() == .acquired)
        #expect(second.tryAcquire() == .heldByAnotherInstance)
    }

    @Test func lockIsReleasedWhenTheHolderGoesAway() {
        var first: SingleInstanceLock? = SingleInstanceLock(fileURL: lockURL)
        #expect(first?.tryAcquire() == .acquired)
        first = nil
        #expect(SingleInstanceLock(fileURL: lockURL).tryAcquire() == .acquired)
    }

    @Test func doesNotFollowASymbolicLinkAtTheLockFile() throws {
        // ロックファイルの場所にシンボリックリンクがあっても、リンク先を作ったりロックしたりしない
        let target = directory.appending(path: "target")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: lockURL, withDestinationURL: target)
        let lock = SingleInstanceLock(fileURL: lockURL)
        guard case .failed = lock.tryAcquire() else {
            Issue.record("expected .failed")
            return
        }
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }
}
