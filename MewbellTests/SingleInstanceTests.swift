import Foundation
import Testing

@testable import Mewbell

struct SingleInstanceLockTests {
    private let lockURL = FileManager.default.temporaryDirectory
        .appending(path: "MewbellTests-\(UUID().uuidString)")
        .appending(path: "instance.lock")

    @Test func acquiresWhenNobodyHoldsTheLock() {
        let lock = SingleInstanceLock(fileURL: lockURL)
        #expect(lock.tryAcquire())
    }

    @Test func secondInstanceCannotAcquireWhileFirstHoldsTheLock() {
        let first = SingleInstanceLock(fileURL: lockURL)
        let second = SingleInstanceLock(fileURL: lockURL)
        #expect(first.tryAcquire())
        #expect(!second.tryAcquire())
    }

    @Test func secondInstanceCanAcquireAfterFirstReleases() {
        let first = SingleInstanceLock(fileURL: lockURL)
        let second = SingleInstanceLock(fileURL: lockURL)
        #expect(first.tryAcquire())
        first.release()
        #expect(second.tryAcquire())
    }

    @Test func lockIsReleasedWhenTheHolderGoesAway() {
        var first: SingleInstanceLock? = SingleInstanceLock(fileURL: lockURL)
        #expect(first?.tryAcquire() == true)
        first = nil
        #expect(SingleInstanceLock(fileURL: lockURL).tryAcquire())
    }

    @Test func acquiringTwiceFromTheSameHolderSucceeds() {
        let lock = SingleInstanceLock(fileURL: lockURL)
        #expect(lock.tryAcquire())
        #expect(lock.tryAcquire())
    }
}
