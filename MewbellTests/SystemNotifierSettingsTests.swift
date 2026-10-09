import Foundation
import Testing

@testable import Mewbell

private let alice = AccountID(host: "github.com", user: "alice")

private func thread(_ id: String) throws -> NotificationThread {
    NotificationThread(
        id: id, reason: "subscribed", updatedAt: Date(timeIntervalSince1970: 0), title: "Thread \(id)", kind: .issue,
        subjectURL: nil, repository: try #require(RepositoryName(fullName: "octo/app")))
}

/// 設定（アカウントごとの通知のオフ、音、基準の取り直し）での `SystemNotifier`。
@MainActor
struct SystemNotifierSettingsTests {
    private let center = FakeUserNotificationCenter()
    private let loaded = FeedPhase.loaded(updatedAt: Date(timeIntervalSince1970: 0))
    private let dave = AccountID(host: "acme.ghe.com", user: "dave")

    private func feed(_ threads: [NotificationThread]) -> FeedState {
        FeedState(phase: loaded, threads: threads)
    }

    @Test func skipsPostingForAnAccountWithNotificationsOff() async throws {
        let notifier = SystemNotifier(center: center, notifies: { $0 != alice })
        let aliceFirst = feed([try thread("1")])
        let daveFirst = feed([try thread("1")])
        notifier.feedChanged(for: alice, from: .loading, to: aliceFirst)
        notifier.feedChanged(for: dave, from: .loading, to: daveFirst)
        notifier.feedChanged(for: alice, from: aliceFirst, to: feed([try thread("1"), try thread("2")]))
        notifier.feedChanged(for: dave, from: daveFirst, to: feed([try thread("1"), try thread("3")]))
        await notifier.waitForPendingWork()
        #expect(center.added.value.map(\.identifier) == ["acme.ghe.com/dave/3"])
    }

    @Test func doesNotPostWhatArrivedWhileOffWhenTurnedBackOn() async throws {
        let enabled = LockedValue(false)
        let notifier = SystemNotifier(center: center, notifies: { _ in enabled.value })
        var current = feed([try thread("1")])
        notifier.feedChanged(for: alice, from: .loading, to: current)
        let whileOff = feed((1...6).compactMap { try? thread(String($0)) })
        notifier.feedChanged(for: alice, from: current, to: whileOff)
        current = whileOff
        enabled.value = true
        notifier.feedChanged(for: alice, from: current, to: feed(current.threads + [try thread("789")]))
        await notifier.waitForPendingWork()
        #expect(center.added.value.map(\.identifier) == ["github.com/alice/789"])
    }

    @Test func retractsOnlyThatAccountWhenNotificationsAreTurnedOff() async {
        let notifier = SystemNotifier(center: center)
        center.delivered.value = ["github.com/alice/1", "github.com/alice/2", "github.com/bob/9"]
        notifier.notificationsDisabled(alice)
        await notifier.waitForPendingWork()
        #expect(center.delivered.value == ["github.com/bob/9"])
    }

    @Test func stillRetractsGoneThreadsWhileOff() async throws {
        let notifier = SystemNotifier(center: center, notifies: { _ in false })
        let first = feed([try thread("1"), try thread("2")])
        notifier.feedChanged(for: alice, from: .loading, to: first)
        await notifier.waitForPendingWork()
        center.delivered.value = ["github.com/alice/2"]
        notifier.feedChanged(for: alice, from: first, to: feed([try thread("1")]))
        await notifier.waitForPendingWork()
        #expect(center.delivered.value.isEmpty)
    }

    @Test func treatsTheFirstFetchAfterAResetAsTheBaseline() async throws {
        let notifier = SystemNotifier(center: center)
        let first = feed([try thread("1"), try thread("2")])
        notifier.feedChanged(for: alice, from: .loading, to: first)
        await notifier.waitForPendingWork()
        center.delivered.value = ["github.com/alice/1", "github.com/alice/2"]
        notifier.resetBaseline(alice)
        await notifier.waitForPendingWork()
        // 取り直しの間は通知を残し、基準の取り直しで今の一覧に無いものだけを消す
        #expect(center.delivered.value.count == 2)
        notifier.feedChanged(for: alice, from: .loading, to: feed([try thread("2"), try thread("4")]))
        await notifier.waitForPendingWork()
        #expect(center.added.value.isEmpty)
        #expect(center.delivered.value == ["github.com/alice/2"])
    }

    @Test func followsTheSoundSetting() async throws {
        let sound = LockedValue(false)
        let notifier = SystemNotifier(center: center, playsSound: { sound.value })
        let first = feed([try thread("1")])
        notifier.feedChanged(for: alice, from: .loading, to: first)
        let second = feed([try thread("1"), try thread("2")])
        notifier.feedChanged(for: alice, from: first, to: second)
        sound.value = true
        notifier.feedChanged(for: alice, from: second, to: feed(second.threads + [try thread("3")]))
        await notifier.waitForPendingWork()
        #expect(center.added.value.map(\.playsSound) == [false, true])
    }
}
