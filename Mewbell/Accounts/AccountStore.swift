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
    /// 読み直しに渡す設定（無効なアカウントと gh の上書き）。nil なら既定値
    @ObservationIgnored private let settings: AppSettings?
    /// 設定ディレクトリを変えるたびに進める。前の設定ディレクトリで始めた読み直しの結果は捨てる
    @ObservationIgnored private var configGeneration = 0
    /// 次の読み直しの前に、すべてのトークンを捨てる（設定ディレクトリを変えたとき）
    @ObservationIgnored private var discardsTokensBeforeNextReload = false
    /// 送った無効化。後から始める読み直しはこれを待つ（すぐ有効に戻したとき、遅れた無効化が取り直したトークンを消さないため）
    @ObservationIgnored private var pendingDisable: Task<Void, Never>?
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
    init(discovery: (any AccountDiscovering)?, settings: AppSettings? = nil, state: DiscoveryState = .checking) {
        self.discovery = discovery
        self.settings = settings
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
        let options = DiscoveryOptions(
            overrides: settings?.ghOverrides ?? GhOverrides(), disabled: settings?.disabledAccounts ?? [])
        let generation = configGeneration
        let discardsTokens = discardsTokensBeforeNextReload
        discardsTokensBeforeNextReload = false
        let pendingDisable = pendingDisable
        reloadTask = Task {
            await pendingDisable?.value
            if discardsTokens {
                await discovery.discardAllTokens()
            }
            await discovery.reload(userInitiated: userInitiated, options: options) { state in
                await self.apply(state, generation: generation)
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

    /// 設定でアカウントを有効・無効にしたとき。無効にしたら読み直しを待たずに一覧から外してトークンを捨て、
    /// 有効にし直したら読み直してトークンを取る。
    func setEnabled(_ enabled: Bool, for id: AccountID) {
        guard enabled else {
            disable(id)
            return
        }
        reload()
    }

    /// gh のパスの上書きを変えたとき。新しい候補で gh を確かめ直す。
    func ghExecutableChanged() {
        reload(userInitiated: true)
    }

    /// gh の設定ディレクトリの上書きを変えたとき。別の `hosts.yml` では同じ `<host>/<user>` でも別のログインのことが
    /// あるので、すべてのポーラーを止め、トークンをすべて捨ててから読み直す。走っている読み直しの結果は捨てる。
    func ghConfigDirectoryChanged() {
        guard discovery != nil, !isTerminating else { return }
        configGeneration += 1
        discardsTokensBeforeNextReload = true
        if state != .checking {
            state = .checking
            onStateChange?(state)
        }
        reload(userInitiated: true)
    }

    private func disable(_ id: AccountID) {
        guard let discovery, !isTerminating else { return }
        apply(state, generation: configGeneration)
        // 走っている読み直しは待たない（すぐにトークンを捨てるため）。無効化どうしは送った順に行う
        let previous = pendingDisable
        pendingDisable = Task {
            await previous?.value
            await discovery.disable(id)
        }
    }

    /// 今の設定で無効なアカウントを `.disabled` にする（無効にした直後に、前の設定で始めた読み直しが終わったときのため）。
    private func applyingSettings(to state: DiscoveryState) -> DiscoveryState {
        settings.map { state.markingDisabled($0.disabledAccounts) } ?? state
    }

    private func apply(_ state: DiscoveryState, generation: Int) {
        // 前の設定ディレクトリで始めた読み直しの結果は捨てる
        guard generation == configGeneration else { return }
        let state = applyingSettings(to: state)
        // 変わっていなければ代入しない（ポップオーバーを開くたびに一覧を描き直さないため）
        guard self.state != state else { return }
        self.state = state
        // 終了処理を始めた後は、走っていた読み直しの結果でポーラーを作り直さない
        guard !isTerminating else { return }
        onStateChange?(state)
    }
}
