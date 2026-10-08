import Foundation
import Observation
import os

/// UI に見せるアカウントの状態。トークンは持たない（`CredentialStore` の中にだけある）。
@MainActor
@Observable
final class AccountStore {
    private(set) var state: DiscoveryState
    private(set) var isReloading = false

    @ObservationIgnored private static let logger = Logger(subsystem: "com.codingfeline.mewbell", category: "Accounts")
    @ObservationIgnored private let discovery: (any AccountDiscovering)?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?

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
        isReloading = true
        // 一覧が出ていないときは、確認中の表示にする
        if !state.hasAccounts {
            state = .checking
        }
        reloadTask = Task {
            await discovery.reload { state in
                await self.apply(state)
            }
            isReloading = false
            reloadTask = nil
        }
    }

    /// 走っている読み直しが終わるのを待つ（テスト用）。
    func waitForReload() async {
        await reloadTask?.value
    }

    func discardCredentials() async {
        await discovery?.discardAllCredentials()
    }

    private func apply(_ state: DiscoveryState) {
        self.state = state
    }
}
