import Foundation
import UserNotifications
import os

/// macOS の通知の許可の状態（`UNAuthorizationStatus` のうち、表示に使うもの）。
enum NotificationAuthorization: Sendable, Equatable {
    case notDetermined
    case denied
    case allowed
}

/// 通知センターへの薄い口。テストでは偽物に差し替える。
protocol UserNotificationCenter: Sendable {
    func requestAuthorization() async -> NotificationAuthorization
    func authorization() async -> NotificationAuthorization
    func add(_ content: ThreadNotificationContent) async
    func removeDelivered(identifiers: [String]) async
    func deliveredIdentifiers() async -> [String]
}

/// `UNUserNotificationCenter` を使う口。
struct LiveUserNotificationCenter: UserNotificationCenter {
    private static let logger = Logger(category: "Notifications")

    private var center: UNUserNotificationCenter { .current() }

    func requestAuthorization() async -> NotificationAuthorization {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            Self.logger.error("Could not request the notification authorization: \(String(describing: error))")
        }
        return await authorization()
    }

    func authorization() async -> NotificationAuthorization {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized, .provisional, .ephemeral: .allowed
        @unknown default: .allowed
        }
    }

    func add(_ content: ThreadNotificationContent) async {
        let notification = UNMutableNotificationContent()
        notification.title = content.title
        notification.subtitle = content.subtitle
        notification.body = content.body
        notification.threadIdentifier = content.threadIdentifier
        notification.userInfo = content.userInfo
        notification.sound = content.playsSound ? .default : nil
        do {
            try await center.add(
                UNNotificationRequest(identifier: content.identifier, content: notification, trigger: nil))
        } catch {
            // 許可が無いときもここに来る
            Self.logger.info("Could not post a notification: \(String(describing: error))")
        }
    }

    func removeDelivered(identifiers: [String]) async {
        guard !identifiers.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func deliveredIdentifiers() async -> [String] {
        await center.deliveredNotifications().map(\.request.identifier)
    }
}
