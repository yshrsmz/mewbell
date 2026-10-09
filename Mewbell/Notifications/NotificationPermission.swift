import Observation

/// macOS の通知の許可の状態を UI に見せる。
@MainActor
@Observable
final class NotificationPermission {
    private(set) var authorization: NotificationAuthorization?

    @ObservationIgnored private let center: (any UserNotificationCenter)?

    /// `center` が nil のときは何もしない（テストのホストや SwiftUI プレビュー用）。
    init(center: (any UserNotificationCenter)?, authorization: NotificationAuthorization? = nil) {
        self.center = center
        self.authorization = authorization
    }

    /// 通知が切られているか（求めていない・求めている途中は false）。
    var isDenied: Bool { authorization == .denied }

    /// 許可を求める（起動時）。
    func request() {
        guard let center else { return }
        Task { authorization = await center.requestAuthorization() }
    }

    /// 許可の状態を読み直す（ポップオーバーを開いたとき）。
    func refresh() {
        guard let center else { return }
        Task { authorization = await center.authorization() }
    }
}
