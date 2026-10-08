import Foundation
import Observation
import os

/// UI に見せるアカウントの状態。トークンは持たない（`CredentialStore` の中にだけある）。
@MainActor
@Observable
final class AccountStore {
    private(set) var state: DiscoveryState

    @ObservationIgnored private static let logger = Logger(category: "Accounts")
    @ObservationIgnored private let discovery: (any AccountDiscovering)?
    private var reloadTask: Task<Void, Never>?

    var isReloading: Bool { reloadTask != nil }

    /// `discovery` が nil のときは読み込みを行わない（テストのホストや SwiftUI プレビュー用）。
    init(discovery: (any AccountDiscovering)?, state: DiscoveryState = .checking) {
        self.discovery = discovery
        self.state = state
    }

    static func live() -> AccountStore {
        AccountStore(discovery: AccountDiscovery.live(credentials: CredentialStore()))
    }

    /// 読み直す。読み直している間に呼ばれたときは何もしない（同じアカウントの gh を同時に走らせないため）。
    func reload() {
        guard let discovery, reloadTask == nil else { return }
        Self.logger.info("Reloading gh accounts")
        // 一覧が出ていないときは、確認中の表示にする
        if !state.hasAccounts {
            state = .checking
        }
        reloadTask = Task {
            await discovery.reload { state in
                await self.apply(state)
            }
            reloadTask = nil
        }
    }

    /// 走っている読み直しが終わるのを待つ（テスト用）。
    func waitForReload() async {
        await reloadTask?.value
    }

    /// 走っている読み直しを止めてから、メモリ上のトークンを捨てる（終了時用）。
    /// 先に止めないと、捨てた後に読み直しがトークンを書き戻すことがある。
    func discardCredentials() async {
        reloadTask?.cancel()
        await reloadTask?.value
        await discovery?.discardAllCredentials()
    }

    private func apply(_ state: DiscoveryState) {
        // 変わっていなければ代入しない（ポップオーバーを開くたびに一覧を描き直さないため）
        guard self.state != state else { return }
        self.state = state
    }
}
