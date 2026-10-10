import Foundation
import Synchronization
import os

/// アカウントごとのトークンの状態。
enum TokenState: Sendable, Equatable {
    case fetching
    case ready
    case unavailable
    /// ユーザーが設定で無効にした（トークンを持たず、`gh auth token` も実行しない）
    case disabled
}

struct AccountStatus: Sendable, Equatable, Identifiable {
    let account: Account
    let tokenState: TokenState

    var id: AccountID { account.id }
}

/// gh とアカウントの全体の状態。
enum DiscoveryState: Sendable, Equatable {
    case checking
    case ghNotFound
    /// バージョンを読めて、対応する版より古い
    case ghOutdated(version: GhVersion)
    /// `gh --version` が失敗した、またはバージョンを読めなかった（一時的な失敗のこともあるので、次の読み直しで確かめ直す）
    case ghUnavailable
    case hostsFileUnreadable(path: String)
    case notLoggedIn
    case accounts([AccountStatus])

    var hasAccounts: Bool {
        if case .accounts = self { true } else { false }
    }

    /// `accounts` を `tokenState` にし、`disabled` に入るものを `.disabled` にした「アカウントあり」。
    static func accounts(
        _ accounts: [Account], disabled: Set<AccountID>, tokenState: (Account) -> TokenState
    ) -> DiscoveryState {
        .accounts(accounts.map { AccountStatus(account: $0, tokenState: tokenState($0)) }).markingDisabled(disabled)
    }

    /// `disabled` に入るアカウントを `.disabled` にする（「アカウントあり」以外はそのまま）。
    func markingDisabled(_ disabled: Set<AccountID>) -> DiscoveryState {
        guard case .accounts(let statuses) = self, !disabled.isEmpty else { return self }
        return .accounts(
            statuses.map { disabled.contains($0.id) ? AccountStatus(account: $0.account, tokenState: .disabled) : $0 })
    }
}

/// 読み直しの開始時点の設定（`AppSettings` から作る）。
struct DiscoveryOptions: Sendable, Equatable {
    var overrides = GhOverrides()
    /// 無効にしたアカウント
    var disabled: Set<AccountID> = []
}

/// gh の検出からトークンの取得までを行う。`AccountStore` から差し替えられるようにプロトコルにする。
protocol AccountDiscovering: Sendable {
    /// 読み直し、途中と最後の状態を `update` に渡す。
    /// `userInitiated` はユーザーが再読み込みを押したとき true（見つかっていない gh をログインシェルで探し直す）。
    func reload(
        userInitiated: Bool, options: DiscoveryOptions, update: @escaping @Sendable (DiscoveryState) async -> Void
    ) async
    /// アカウントのトークンを捨て、`enable` されるまで受け取らない（設定で無効にしたとき）。
    func disable(_ id: AccountID) async
    /// `disable` を取り消す（設定で有効にし直したとき。トークンは次の読み直しで取る）。
    func enable(_ id: AccountID) async
    /// すべてのトークンを捨てる（設定ディレクトリの上書きを変えたとき）。
    func discardAllTokens() async
    /// トークンをすべて捨て、以後は受け取らない（アプリの終了時）。
    func closeCredentials() async
    /// 最後の読み直しでの gh の検出の結果（gh は実行しない）。
    func ghDiagnostics() async -> GhDiagnostics
}

actor AccountDiscovery: AccountDiscovering, TokenProviding {
    private static let logger = Logger(category: "Accounts")

    private let locator: GhLocator
    private let runner: any ProcessRunning
    /// 子プロセスに渡す環境（設定ディレクトリを上書きしたときは、読み直しごとに `GH_CONFIG_DIR` を足す）
    private let environment: [String: String]
    /// 設定で上書きしないときの設定ディレクトリと決め方
    private let configDirectory: GhConfigDirectory.Resolved
    private let credentials: CredentialStore
    /// `gh --version` で対応を確かめた gh の実体のパスと、そのバージョン
    private var verifiedGh: (path: URL, version: GhVersion)?
    /// 最後の読み直しでの gh の検出の結果
    private var lastGhDiagnostics = GhDiagnostics()
    /// 最後の読み直しで使った子プロセスの環境（401 の後の取り直しでも同じ設定ディレクトリを使うため）
    private var currentEnvironment: [String: String]
    /// `verifiedGh` を確かめたときの設定ディレクトリ（変わったら `gh --version` からやり直す）
    private var verifiedConfigDirectory: URL?
    /// アカウントごとの走っている `gh auth token`（読み直しと取り直しで共有する）
    private var inFlightTokenFetches: [AccountID: TokenFetch] = [:]
    /// 最後の読み直しで `hosts.yml` にあったアカウント。ここに無いアカウントのトークンは保存しない
    /// （取得の途中でアカウントが消えたときに、捨てたトークンを書き戻さないため）
    private var knownAccountIDs: Set<AccountID> = []
    /// 無効なアカウント。`disable` と `enable` で出し入れし、読み直しでは設定の値を足すだけにする
    /// （読み直しより先に届いた `disable` を、読み直しが古い設定で消さないため）
    private var disabledIDs: Set<AccountID> = []
    /// `discardAllTokens` で進める。進む前に始めた `gh auth token` の結果は保存しない（前の設定ディレクトリのものなので）
    private var tokenEpoch = 0

    init(
        locator: GhLocator,
        runner: any ProcessRunning,
        environment: [String: String],
        configDirectory: GhConfigDirectory.Resolved,
        credentials: CredentialStore
    ) {
        self.locator = locator
        self.runner = runner
        self.environment = environment
        self.configDirectory = configDirectory
        self.credentials = credentials
        currentEnvironment = environment
    }

    /// 実際の gh と `hosts.yml` を使う。
    static func live(credentials: CredentialStore) -> AccountDiscovery {
        let processEnvironment = ProcessInfo.processInfo.environment
        let environment = GhEnvironment.make(from: processEnvironment)
        let runner = SubprocessRunner()
        return AccountDiscovery(
            locator: GhLocator(runner: runner, environment: environment),
            runner: runner,
            environment: environment,
            configDirectory: GhConfigDirectory.resolve(
                environment: processEnvironment, homeDirectory: FileManager.default.homeDirectoryForCurrentUser),
            credentials: credentials)
    }

    func reload(
        userInitiated: Bool, options: DiscoveryOptions, update: @escaping @Sendable (DiscoveryState) async -> Void
    ) async {
        disabledIDs.formUnion(options.disabled)
        let state = await discover(userInitiated: userInitiated, options: options, update: update)
        // アカウントを使えない状態になったら、持っているトークンをすべて捨てる
        if !state.hasAccounts {
            knownAccountIDs = []
            await credentials.removeAll()
        }
        await update(state)
    }

    func closeCredentials() async {
        await credentials.close()
    }

    func ghDiagnostics() async -> GhDiagnostics {
        lastGhDiagnostics
    }

    func disable(_ id: AccountID) async {
        // 走っている `gh auth token` の結果も、`knownAccountIDs` に無いので保存されない
        disabledIDs.insert(id)
        knownAccountIDs.remove(id)
        await credentials.remove(id)
    }

    func enable(_ id: AccountID) async {
        disabledIDs.remove(id)
    }

    func discardAllTokens() async {
        knownAccountIDs = []
        // 走っている取得は前の設定ディレクトリのものなので、止めて、合流させず、結果も保存しない
        // （取り直しを待っているポーラーは、設定ディレクトリを変えたときにすべて止めている）
        for fetch in inFlightTokenFetches.values {
            fetch.task.cancel()
        }
        inFlightTokenFetches.removeAll()
        tokenEpoch += 1
        await credentials.removeAll()
    }

    func currentToken(for id: AccountID) async -> AccessToken? {
        await credentials.token(for: id)
    }

    func discardToken(for id: AccountID) async {
        await credentials.remove(id)
    }

    /// アカウントのトークンを捨てて gh から取り直し、取れたトークンを返す（API が 401 を返したときなど）。
    /// 同じアカウントの取得が走っていれば、その結果を共有する。
    func refreshToken(for id: AccountID) async -> AccessToken? {
        await credentials.remove(id)
        guard knownAccountIDs.contains(id) else { return nil }
        guard let ghPath = verifiedGh?.path else {
            Self.logger.error("Cannot refresh the token of \(id) before gh is verified")
            return nil
        }
        let client = GhClient(executable: ghPath, runner: runner, environment: currentEnvironment)
        return await fetchToken(for: id, using: client)
    }

    /// `gh auth token` を実行して、取れたトークンを保存する。同じアカウントの取得が走っていれば、その結果を待つ。
    /// 取得を始めた呼び出し元がキャンセルされたら gh も止める（合流しただけの呼び出し元のキャンセルでは止めない）。
    private func fetchToken(for id: AccountID, using client: GhClient) async -> AccessToken? {
        let epoch = tokenEpoch
        let token: AccessToken?
        if let running = inFlightTokenFetches[id] {
            running.isShared.withLock { $0 = true }
            token = await running.task.value
        } else {
            let fetch = TokenFetch(task: Task { await client.token(host: id.host, user: id.user) })
            inFlightTokenFetches[id] = fetch
            token = await withTaskCancellationHandler {
                await fetch.task.value
            } onCancel: {
                // 合流した呼び出し元がいれば、その結果を奪わないよう gh は止めない
                if !fetch.isShared.withLock({ $0 }) {
                    fetch.task.cancel()
                }
            }
            if inFlightTokenFetches[id] === fetch {
                inFlightTokenFetches[id] = nil
            }
        }
        // 合流した呼び出し元も保存する（返したトークンが `CredentialStore` にあることを、誰が先に戻っても保証するため）
        guard let token, knownAccountIDs.contains(id), epoch == tokenEpoch else { return nil }
        await credentials.set(token, for: id)
        return token
    }

    private func discover(
        userInitiated: Bool, options: DiscoveryOptions, update: @Sendable (DiscoveryState) async -> Void
    ) async -> DiscoveryState {
        // 途中で返ったときに前の読み直しの値を残さないよう、分かった値だけを入れて最後に書き直す
        var diagnostics = GhDiagnostics()
        defer { lastGhDiagnostics = diagnostics }
        guard
            let location = await locator.locate(
                overridePath: options.overrides.executablePath, retryLoginShell: userInitiated)
        else {
            verifiedGh = nil
            return .ghNotFound
        }
        diagnostics.executable = location
        let resolvedConfigDirectory: GhConfigDirectory.Resolved
        switch resolveConfigDirectory(override: options.overrides.configDirectory) {
        case .success(let resolved): resolvedConfigDirectory = resolved
        case .failure(let unusable): return unusable.state
        }
        diagnostics.configDirectory = resolvedConfigDirectory
        let configDirectory = resolvedConfigDirectory.url
        let environment = GhEnvironment.make(
            from: environment, configDirectory: resolvedConfigDirectory.source == .override ? configDirectory : nil)
        currentEnvironment = environment
        if verifiedConfigDirectory != configDirectory {
            verifiedGh = nil
            verifiedConfigDirectory = configDirectory
        }
        // gh は hosts.yml を解釈できないと --version でも失敗するので、バージョンより先に読む
        let hostsURL = configDirectory.appending(path: "hosts.yml")
        let hostsFile: HostsFile?
        do {
            hostsFile = try HostsFile.load(from: hostsURL)
        } catch {
            Self.logger.error("Could not read hosts.yml: \(String(describing: error))")
            return .hostsFileUnreadable(path: hostsURL.path)
        }

        let client = GhClient(executable: location.url, runner: runner, environment: environment)
        let (unusable, version) = await verifyVersion(of: location.url, using: client)
        diagnostics.version = version
        if let unusable {
            return unusable
        }

        let accounts = hostsFile.map(Account.accounts(from:)) ?? []
        guard !accounts.isEmpty else { return .notLoggedIn }

        // 無効なアカウントは gh を呼ばず、持っているトークンも捨てる（読み直しの途中で無効にしたものも含める）。
        // 返す状態もこの時点の集合で作る（取得の途中で有効に戻したアカウントを、トークンが無いまま「使える」にしないため）
        let disabled = disabledIDs
        let enabled = accounts.filter { !disabled.contains($0.id) }
        knownAccountIDs = Set(enabled.map(\.id))
        let held = await credentials.retainOnly(knownAccountIDs)
        let pending = enabled.filter { !held.contains($0.id) }
        if !pending.isEmpty {
            await update(.accounts(accounts, disabled: disabled) { held.contains($0.id) ? .ready : .fetching })
        }

        let failed = await fetchTokens(for: pending, using: client)
        return .accounts(accounts, disabled: disabled) { failed.contains($0.id) ? .unavailable : .ready }
    }

    /// 使う設定ディレクトリ。設定で上書きした設定ディレクトリが使えなければ、ほかの候補に移らない
    /// （別の gh のログインを黙って使わないため）。読むのも gh に渡すのも、確かめた実体のパスにする。
    private func resolveConfigDirectory(override: String?) -> Result<
        GhConfigDirectory.Resolved, UnusableConfigDirectory
    > {
        guard let override else { return .success(configDirectory) }
        guard let url = ConfigDirectoryValidator.validate(override) else {
            Self.logger.error("The overridden gh config directory is not usable")
            let hostsFile = URL(filePath: override, directoryHint: .isDirectory).appending(path: "hosts.yml")
            return .failure(UnusableConfigDirectory(state: .hostsFileUnreadable(path: hostsFile.path)))
        }
        return .success(GhConfigDirectory.Resolved(url: url, source: .override))
    }

    /// gh のパスが前回確かめたものと違えば `gh --version` で確かめる。使えなければその状態と、読めたバージョンを返す。
    private func verifyVersion(of ghPath: URL, using client: GhClient) async -> (
        unusable: DiscoveryState?, version: GhVersion?
    ) {
        if let verifiedGh, verifiedGh.path == ghPath { return (nil, verifiedGh.version) }
        verifiedGh = nil
        guard let version = await client.version() else { return (.ghUnavailable, nil) }
        guard version.isSupported else { return (.ghOutdated(version: version), version) }
        verifiedGh = (ghPath, version)
        return (nil, version)
    }

    /// アカウントごとの `gh auth token` を並べて実行し、取れたトークンを保存する。取れなかったアカウントを返す。
    private func fetchTokens(for accounts: [Account], using client: GhClient) async -> Set<AccountID> {
        await withTaskGroup(of: (AccountID, Bool).self) { group in
            for account in accounts {
                group.addTask { (account.id, await self.fetchToken(for: account.id, using: client) != nil) }
            }
            var failed: Set<AccountID> = []
            for await (id, fetched) in group where !fetched {
                failed.insert(id)
            }
            return failed
        }
    }
}

/// 上書きした設定ディレクトリが使えなかったときの、全体の状態。
private struct UnusableConfigDirectory: Error {
    let state: DiscoveryState
}

/// 走っている `gh auth token` と、ほかの呼び出し元が合流したかどうか。
private final class TokenFetch: Sendable {
    let task: Task<AccessToken?, Never>
    let isShared = Mutex(false)

    init(task: Task<AccessToken?, Never>) {
        self.task = task
    }
}
