import Foundation
import Testing

@testable import Mewbell

struct SingleInstanceLockTests {
    private let lockURL = FileManager.default.temporaryDirectory
        .appending(path: "MewbellTests-\(UUID().uuidString)")
        .appending(path: "instance.lock")

    @Test func acquiresWhenNobodyHoldsTheLock() {
        let lock = SingleInstanceLock(fileURL: lockURL)
        #expect(lock.tryAcquire() == .acquired)
    }

    @Test func secondInstanceCannotAcquireWhileFirstHoldsTheLock() {
        let first = SingleInstanceLock(fileURL: lockURL)
        let second = SingleInstanceLock(fileURL: lockURL)
        #expect(first.tryAcquire() == .acquired)
        #expect(second.tryAcquire() == .heldByAnotherInstance)
    }

    @Test func secondInstanceCanAcquireAfterFirstReleases() {
        let first = SingleInstanceLock(fileURL: lockURL)
        let second = SingleInstanceLock(fileURL: lockURL)
        #expect(first.tryAcquire() == .acquired)
        first.release()
        #expect(second.tryAcquire() == .acquired)
    }

    @Test func lockIsReleasedWhenTheHolderGoesAway() {
        var first: SingleInstanceLock? = SingleInstanceLock(fileURL: lockURL)
        #expect(first?.tryAcquire() == .acquired)
        first = nil
        #expect(SingleInstanceLock(fileURL: lockURL).tryAcquire() == .acquired)
    }

    @Test func acquiringTwiceFromTheSameHolderSucceeds() {
        let lock = SingleInstanceLock(fileURL: lockURL)
        #expect(lock.tryAcquire() == .acquired)
        #expect(lock.tryAcquire() == .acquired)
    }

    @Test func reportsFailureWhenTheLockFileCannotBeOpened() throws {
        // ロックファイルの置き場所に通常ファイルがあり、ディレクトリを作れない
        let blocker = FileManager.default.temporaryDirectory.appending(path: "MewbellTests-\(UUID().uuidString)")
        try Data().write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let lock = SingleInstanceLock(fileURL: blocker.appending(path: "instance.lock"))
        guard case .failed = lock.tryAcquire() else {
            Issue.record("expected .failed")
            return
        }
    }
}
