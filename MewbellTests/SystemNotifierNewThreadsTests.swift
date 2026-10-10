import Foundation
import Testing

@testable import Mewbell

private let alice = AccountID(host: "github.com", user: "alice")

private func thread(_ id: String, updatedAt: TimeInterval = 0) throws -> NotificationThread {
    NotificationThread(
        id: id, reason: "subscribed", updatedAt: Date(timeIntervalSince1970: updatedAt), title: "Thread \(id)",
        kind: .issue, subjectURL: nil, repository: try #require(RepositoryName(fullName: "octo/app")))
}

/// `SystemNotifier.onNewThreads`（一覧の折りたたみを開くための新着の知らせ）。
@MainActor
struct SystemNotifierNewThreadsTests {
    private let center = FakeUserNotificationCenter()
    private let loaded = FeedPhase.loaded(updatedAt: Date(timeIntervalSince1970: 0))

    private func feed(_ threads: [NotificationThread]) -> FeedState {
        FeedState(phase: loaded, threads: threads)
    }

    private func notifier(
        notifies: Bool = true, collecting received: LockedValue<[[String]]>
    ) -> SystemNotifier {
        let notifier = SystemNotifier(center: center, notifies: { _ in notifies })
        notifier.onNewThreads = { account, threads in
            #expect(account == alice)
            received.value.append(threads.map(\.id))
        }
        return notifier
    }

    @Test func staysQuietForTheBaseline() throws {
        let received = LockedValue<[[String]]>([])
        let notifier = notifier(collecting: received)
        notifier.feedChanged(for: alice, from: .loading, to: feed([try thread("1")]))
        #expect(received.value.isEmpty)
    }

    @Test func reportsNewAndUpdatedThreads() throws {
        let received = LockedValue<[[String]]>([])
        let notifier = notifier(collecting: received)
        let first = feed([try thread("1"), try thread("2")])
        notifier.feedChanged(for: alice, from: .loading, to: first)
        let second = feed([try thread("1"), try thread("2", updatedAt: 60), try thread("3")])
        notifier.feedChanged(for: alice, from: first, to: second)
        #expect(received.value == [["2", "3"]])
    }

    @Test func reportsEvenWhenNotificationsAreOff() async throws {
        let received = LockedValue<[[String]]>([])
        let notifier = notifier(notifies: false, collecting: received)
        let first = feed([try thread("1")])
        notifier.feedChanged(for: alice, from: .loading, to: first)
        notifier.feedChanged(for: alice, from: first, to: feed([try thread("1"), try thread("2")]))
        await notifier.waitForPendingWork()
        #expect(received.value == [["2"]])
        #expect(center.added.value.isEmpty)
    }

    @Test func ignoresAThreadThatCameBackUnchanged() throws {
        let received = LockedValue<[[String]]>([])
        let notifier = notifier(collecting: received)
        let first = feed([try thread("1"), try thread("2")])
        notifier.feedChanged(for: alice, from: .loading, to: first)
        notifier.threadRemoved("2", for: alice)
        let without = feed([try thread("1")])
        notifier.feedChanged(for: alice, from: first, to: without)
        notifier.feedChanged(for: alice, from: without, to: first)
        #expect(received.value.isEmpty)
    }

    @Test func staysQuietForTheFirstFetchAfterAReset() throws {
        let received = LockedValue<[[String]]>([])
        let notifier = notifier(collecting: received)
        notifier.feedChanged(for: alice, from: .loading, to: feed([try thread("1")]))
        notifier.resetBaseline(alice)
        notifier.feedChanged(for: alice, from: .loading, to: feed([try thread("1"), try thread("5")]))
        #expect(received.value.isEmpty)
    }
}
