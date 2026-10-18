import Foundation
import Testing

@testable import Mewbell

private let alice = AccountID(host: "github.com", user: "alice")

private func thread(_ id: String) throws -> NotificationThread {
    NotificationThread(
        id: id, reason: "subscribed", updatedAt: Date(timeIntervalSince1970: 0), title: "Thread \(id)", kind: .issue,
        subjectURL: nil, repository: try #require(RepositoryName(fullName: "octo/app")), detailsSubject: nil)
}

/// 設定（アカウントごとの通知のオフ、音）での `SystemNotifier`。
@MainActor
struct SystemNotifierSettingsTests {
    private let center = FakeUserNotificationCenter()
    private let dave = AccountID(host: "acme.ghe.com", user: "dave")

    /// 通知のオフはアカウントごとに、呼ぶたびに読み直す。オフの間の新着はためず、オンに戻しても出さない
    @Test func skipsPostingForAnAccountWithNotificationsOff() async throws {
        let aliceEnabled = LockedValue(false)
        let notifier = SystemNotifier(center: center, notifies: { $0 != alice || aliceEnabled.value })
        notifier.threadsChanged(for: alice, posted: (2...6).compactMap { try? thread(String($0)) }, retracted: [])
        notifier.threadsChanged(for: dave, posted: [try thread("3")], retracted: [])
        aliceEnabled.value = true
        notifier.threadsChanged(for: alice, posted: [try thread("789")], retracted: [])
        await notifier.waitForPendingWork()
        #expect(center.added.value.map(\.identifier) == ["acme.ghe.com/dave/3", "github.com/alice/789"])
    }

    @Test func stillRetractsGoneThreadsWhileOff() async throws {
        let notifier = SystemNotifier(center: center, notifies: { _ in false })
        center.delivered.value = ["github.com/alice/2"]
        notifier.threadsChanged(for: alice, posted: [try thread("3")], retracted: ["2"])
        await notifier.waitForPendingWork()
        #expect(center.delivered.value.isEmpty)
        #expect(center.added.value.isEmpty)
    }

    @Test func followsTheSoundSetting() async throws {
        let sound = LockedValue(false)
        let notifier = SystemNotifier(center: center, playsSound: { sound.value })
        notifier.threadsChanged(for: alice, posted: [try thread("2")], retracted: [])
        sound.value = true
        notifier.threadsChanged(for: alice, posted: [try thread("3")], retracted: [])
        await notifier.waitForPendingWork()
        #expect(center.added.value.map(\.playsSound) == [false, true])
    }
}
