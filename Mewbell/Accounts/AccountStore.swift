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
    /// 読み直している間に要求が来たか（終わった後にもう一度読み直す）
    @ObservationIgnored private var reloadRequested = false
    /// 読み直している間に来た要求に、ユーザーの再読み込みが含まれるか
    @ObservationIgnored private var queuedReloadIsUserInitiated = false
    /// 終了処理を始めたか（以後は読み直さない）
    @ObservationIgnored private var isTerminating = false
    /// 状態が変わったときに呼ぶ（ポーラーの起動・停止に使う）
    @ObservationIgnored var onStateChange: ((DiscoveryState) -> Void)?

    var isReloading: Bool { reloadTask != nil }

    /// `discovery` が nil のときは読み込みを行わない（テストのホストや SwiftUI プレビュー用）。
    init(discovery: (any AccountDiscovering)?, state: DiscoveryState = .checking) {
        self.discovery = discovery
        self.state = state
    }

    /// 読み直す。読み直している間に呼ばれたときは、同じアカウントの gh を同時に走らせないよう、
    /// 今の読み直しが終わってからもう一度読み直す（ログイン直後に開いたポップオーバーの要求を取りこぼさないため）。
    /// `userInitiated` が true（再読み込みボタン）なら、一覧が出ていないときに確認中の表示にし、
    /// 見つかっていない gh をログインシェルで探し直す。
    /// ポップオーバーを開いたとき（false）は今の表示を残す（開くたびに案内がちらつかないように）。
    func reload(userInitiated: Bool = false) {
        guard let discovery, !isTerminating else { return }
        guard reloadTask == nil else {
            reloadRequested = true
            queuedReloadIsUserInitiated = queuedReloadIsUserInitiated || userInitiated
            return
        }
        reloadRequested = false
        queuedReloadIsUserInitiated = false
        Self.logger.info("Reloading gh accounts")
        if userInitiated && !state.hasAccounts {
            state = .checking
        }
        reloadTask = Task {
            await discovery.reload(userInitiated: userInitiated) { state in
                await self.apply(state)
            }
            reloadTask = nil
            if reloadRequested {
                reload(userInitiated: queuedReloadIsUserInitiated)
            }
        }
    }

    /// 読み直しが（続けて要求された分も含めて）終わるのを待つ（テスト用）。
    func waitForReload() async {
        while let reloadTask {
            await reloadTask.value
        }
    }

    /// 終了時に、読み直しを止めてメモリ上のトークンを捨てる。
    /// 走っている読み直しの終わりは待たない（ログインシェルの検索などで終了が遅れないように）。
    /// その代わり、捨てた後は `CredentialStore` がトークンを受け取らない。
    func discardCredentials() async {
        isTerminating = true
        reloadRequested = false
        reloadTask?.cancel()
        await discovery?.closeCredentials()
    }

    private func apply(_ state: DiscoveryState) {
        // 変わっていなければ代入しない（ポップオーバーを開くたびに一覧を描き直さないため）
        guard self.state != state else { return }
        self.state = state
        // 終了処理を始めた後は、走っていた読み直しの結果でポーラーを作り直さない
        guard !isTerminating else { return }
        onStateChange?(state)
    }
}
