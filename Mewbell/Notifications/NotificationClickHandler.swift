import Foundation
import UserNotifications
import os

/// 通知センターの delegate。前面にいるときもバナーを出し、クリックされた通知のスレッドを開く。
final class NotificationClickHandler: NSObject, UNUserNotificationCenterDelegate, Sendable {
    private static let logger = Logger(category: "Notifications")
    private let onOpen: @MainActor @Sendable (ThreadOpenRequest) -> Void

    init(onOpen: @escaping @MainActor @Sendable (ThreadOpenRequest) -> Void) {
        self.onOpen = onOpen
    }

    // async 版は ObjC のサンクの生成でコンパイラが落ちることがある（RedirectRejectingDelegate と同じ）ので、
    // completion handler 版を使う
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        defer { completionHandler() }
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        // 通知センターから戻ってきた値は信用せず、検証し直してから使う
        guard let request = ThreadOpenRequest(userInfo: response.notification.request.content.userInfo) else {
            Self.logger.error("Ignored a notification click with invalid user info")
            return
        }
        let onOpen = onOpen
        Task { @MainActor in onOpen(request) }
    }
}
