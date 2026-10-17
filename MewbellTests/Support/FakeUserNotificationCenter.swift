import Foundation

@testable import Mewbell

/// 出ている通知の識別子を覚えておき、操作を記録する `UserNotificationCenter`。
final class FakeUserNotificationCenter: UserNotificationCenter {
    let delivered = LockedValue<Set<String>>([])
    let added = LockedValue<[ThreadNotificationContent]>([])
    /// `removeDelivered(identifiers:)` に渡された識別子（呼ばれた順）
    let removals = LockedValue<[Set<String>]>([])
    let status = LockedValue(NotificationAuthorization.notDetermined)

    func requestAuthorization() async -> NotificationAuthorization {
        status.withLock { $0 = $0 == .notDetermined ? .allowed : $0 }
        return status.value
    }

    func authorization() async -> NotificationAuthorization {
        status.value
    }

    func add(_ content: ThreadNotificationContent) async {
        added.withLock { $0.append(content) }
        delivered.withLock { _ = $0.insert(content.identifier) }
    }

    func removeDelivered(identifiers: [String]) async {
        removals.withLock { $0.append(Set(identifiers)) }
        delivered.withLock { $0.subtract(identifiers) }
    }

    func deliveredIdentifiers() async -> [String] {
        Array(delivered.value)
    }
}
