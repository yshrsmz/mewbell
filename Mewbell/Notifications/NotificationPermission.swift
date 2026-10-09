import Observation

/// macOS の通知の許可の状態を UI に見せる。
@MainActor
@Observable
final class NotificationPermission {
    private(set) var authorization: NotificationAuthorization?

    @ObservationIgnored private let center: (any UserNotificationCenter)?
    /// 許可を求めている途中か（その間の読み直しで、求めた結果を古い値で上書きしないように）
    @ObservationIgnored private var isRequesting = false

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
        isRequesting = true
        Task {
            authorization = await center.requestAuthorization()
            isRequesting = false
        }
    }

    /// 許可の状態を読み直す（ポップオーバーを開いたとき）。
    func refresh() {
        guard let center, !isRequesting else { return }
        Task {
            let value = await center.authorization()
            // 読んでいる間に許可を求め始めたら、そちらの結果を待つ
            guard !isRequesting else { return }
            authorization = value
        }
    }
}
