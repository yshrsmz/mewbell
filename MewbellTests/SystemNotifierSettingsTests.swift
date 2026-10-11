import Foundation
import Testing

@testable import Mewbell

private let alice = AccountID(host: "github.com", user: "alice")

private func thread(_ id: String) throws -> NotificationThread {
    NotificationThread(
        id: id, reason: "subscribed", updatedAt: Date(timeIntervalSince1970: 0), title: "Thread \(id)", kind: .issue,
        subjectURL: nil, repository: try #require(RepositoryName(fullName: "octo/app")), subjectNumber: nil)
}

/// 設定（アカウントごとの通知のオフ、音）での `SystemNotifier`。
@MainActor
struct SystemNotifierSettingsTests {
    private let center = FakeUserNotificationCenter()
    private let dave = AccountID(host: "acme.ghe.com", user: "dave")

    @Test func skipsPostingForAnAccountWithNotificationsOff() async throws {
        let notifier = SystemNotifier(center: center, notifies: { $0 != alice })
        notifier.threadsChanged(for: alice, posted: [try thread("2")], retracted: [])
        notifier.threadsChanged(for: dave, posted: [try thread("3")], retracted: [])
        await notifier.waitForPendingWork()
        #expect(center.added.value.map(\.identifier) == ["acme.ghe.com/dave/3"])
    }

    @Test func postsAgainWhenTurnedBackOn() async throws {
        let enabled = LockedValue(false)
        let notifier = SystemNotifier(center: center, notifies: { _ in enabled.value })
        notifier.threadsChanged(for: alice, posted: (2...6).compactMap { try? thread(String($0)) }, retracted: [])
        enabled.value = true
        notifier.threadsChanged(for: alice, posted: [try thread("789")], retracted: [])
        await notifier.waitForPendingWork()
        #expect(center.added.value.map(\.identifier) == ["github.com/alice/789"])
    }

    @Test func retractsOnlyThatAccountWhenNotificationsAreTurnedOff() async {
        let notifier = SystemNotifier(center: center)
        center.delivered.value = ["github.com/alice/1", "github.com/alice/2", "github.com/bob/9"]
        notifier.retractAll(for: alice)
        await notifier.waitForPendingWork()
        #expect(center.delivered.value == ["github.com/bob/9"])
    }

    @Test func stillRetractsGoneThreadsWhileOff() async throws {
        let notifier = SystemNotifier(center: center, notifies: { _ in false })
        center.delivered.value = ["github.com/alice/2"]
        notifier.threadsChanged(for: alice, posted: [try thread("3")], retracted: ["2"])
        await notifier.waitForPendingWork()
        #expect(center.delivered.value.isEmpty)
        #expect(center.added.value.isEmpty)
    }

    @Test func keepsNotificationsOfTheNewBaseline() async {
        let notifier = SystemNotifier(center: center)
        center.delivered.value = ["github.com/alice/1", "github.com/alice/2"]
        // 基準の取り直しで、今の一覧に無いものだけを消す
        notifier.baselineSet(for: alice, keeping: ["2", "4"])
        await notifier.waitForPendingWork()
        #expect(center.added.value.isEmpty)
        #expect(center.delivered.value == ["github.com/alice/2"])
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
