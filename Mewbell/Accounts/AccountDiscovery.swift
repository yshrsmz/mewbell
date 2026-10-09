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

    /// 無効なアカウントを `.disabled` に、それ以外を `tokenState` にした「アカウントあり」。
    static func accounts(
        _ accounts: [Account], disabled: Set<AccountID>, tokenState: (Account) -> TokenState
    ) -> DiscoveryState {
        .accounts(
            accounts.map { account in
                AccountStatus(
                    account: account, tokenState: disabled.contains(account.id) ? .disabled : tokenState(account))
            })
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
    /// アカウントのトークンを捨て、次の読み直しまで受け取らない（設定で無効にしたとき）。
    func disable(_ id: AccountID) async
    /// すべてのトークンを捨てる（設定ディレクトリの上書きを変えたとき）。
    func discardAllTokens() async
    /// トークンをすべて捨て、以後は受け取らない（アプリの終了時）。
    func closeCredentials() async
}

extension AccountDiscovering {
    func reload(userInitiated: Bool, update: @escaping @Sendable (DiscoveryState) async -> Void) async {
        await reload(userInitiated: userInitiated, options: DiscoveryOptions(), update: update)
    }
}

actor AccountDiscovery: AccountDiscovering, TokenProviding {
    private static let logger = Logger(category: "Accounts")

    private let locator: GhLocator
    private let runner: any ProcessRunning
    /// 子プロセスに渡す環境（設定ディレクトリを上書きしたときは、読み直しごとに `GH_CONFIG_DIR` を足す）
    private let environment: [String: String]
    /// 設定で上書きしないときの設定ディレクトリ
    private let configDirectory: URL
    private let credentials: CredentialStore
    /// `gh --version` で対応を確かめた gh の実体のパス
    private var verifiedGhPath: URL?
    /// 最後の読み直しで使った子プロセスの環境（401 の後の取り直しでも同じ設定ディレクトリを使うため）
    private var currentEnvironment: [String: String]
    /// `verifiedGhPath` を確かめたときの設定ディレクトリ（変わったら `gh --version` からやり直す）
    private var verifiedConfigDirectory: URL?
    /// アカウントごとの走っている `gh auth token`（読み直しと取り直しで共有する）
    private var inFlightTokenFetches: [AccountID: TokenFetch] = [:]
    /// 最後の読み直しで `hosts.yml` にあったアカウント。ここに無いアカウントのトークンは保存しない
    /// （取得の途中でアカウントが消えたときに、捨てたトークンを書き戻さないため）
    private var knownAccountIDs: Set<AccountID> = []

    init(
        locator: GhLocator,
        runner: any ProcessRunning,
        environment: [String: String],
        configDirectory: URL,
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

    func disable(_ id: AccountID) async {
        // 走っている `gh auth token` の結果も、`knownAccountIDs` に無いので保存されない
        knownAccountIDs.remove(id)
        await credentials.remove(id)
    }

    func discardAllTokens() async {
        knownAccountIDs = []
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
        guard let ghPath = verifiedGhPath else {
            Self.logger.error("Cannot refresh the token of \(id) before gh is verified")
            return nil
        }
        let client = GhClient(executable: ghPath, runner: runner, environment: currentEnvironment)
        return await fetchToken(for: id, using: client)
    }

    /// `gh auth token` を実行して、取れたトークンを保存する。同じアカウントの取得が走っていれば、その結果を待つ。
    /// 取得を始めた呼び出し元がキャンセルされたら gh も止める（合流しただけの呼び出し元のキャンセルでは止めない）。
    private func fetchToken(for id: AccountID, using client: GhClient) async -> AccessToken? {
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
            inFlightTokenFetches[id] = nil
        }
        // 合流した呼び出し元も保存する（返したトークンが `CredentialStore` にあることを、誰が先に戻っても保証するため）
        guard let token, knownAccountIDs.contains(id) else { return nil }
        await credentials.set(token, for: id)
        return token
    }

    private func discover(
        userInitiated: Bool, options: DiscoveryOptions, update: @Sendable (DiscoveryState) async -> Void
    ) async -> DiscoveryState {
        guard
            let ghPath = await locator.locate(
                overridePath: options.overrides.executablePath, retryLoginShell: userInitiated)
        else {
            verifiedGhPath = nil
            return .ghNotFound
        }
        let configDirectory: URL
        switch resolveConfigDirectory(options.overrides.configDirectory) {
        case .success(let url): configDirectory = url
        case .failure(let unusable): return .hostsFileUnreadable(path: unusable.hostsFile.path)
        }
        let environment = GhEnvironment.make(
            from: environment, configDirectory: options.overrides.configDirectory != nil ? configDirectory : nil)
        currentEnvironment = environment
        if verifiedConfigDirectory != configDirectory {
            verifiedGhPath = nil
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

        let client = GhClient(executable: ghPath, runner: runner, environment: environment)
        if verifiedGhPath != ghPath {
            verifiedGhPath = nil
            let version = await client.version()
            guard let version else { return .ghUnavailable }
            guard version.isSupported else { return .ghOutdated(version: version) }
            verifiedGhPath = ghPath
        }

        let accounts = hostsFile.map(Account.accounts(from:)) ?? []
        guard !accounts.isEmpty else { return .notLoggedIn }

        // 無効なアカウントは gh を呼ばず、持っているトークンも捨てる
        let enabled = accounts.filter { !options.disabled.contains($0.id) }
        knownAccountIDs = Set(enabled.map(\.id))
        let held = await credentials.retainOnly(knownAccountIDs)
        let pending = enabled.filter { !held.contains($0.id) }
        if !pending.isEmpty {
            await update(
                .accounts(accounts, disabled: options.disabled) { held.contains($0.id) ? .ready : .fetching })
        }

        let failed = await fetchTokens(for: pending, using: client)
        return .accounts(accounts, disabled: options.disabled) { failed.contains($0.id) ? .unavailable : .ready }
    }

    /// 設定で上書きした設定ディレクトリが使えなければ、ほかの候補に移らない（別の gh のログインを黙って使わないため）。
    private func resolveConfigDirectory(_ override: String?) -> Result<URL, UnusableConfigDirectory> {
        guard let override else { return .success(configDirectory) }
        let url = URL(filePath: override, directoryHint: .isDirectory)
        guard ConfigDirectoryValidator.validate(override) else {
            Self.logger.error("The overridden gh config directory is not usable")
            return .failure(UnusableConfigDirectory(hostsFile: url.appending(path: "hosts.yml")))
        }
        return .success(url)
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

/// 走っている `gh auth token` と、ほかの呼び出し元が合流したかどうか。
private final class TokenFetch: Sendable {
    let task: Task<AccessToken?, Never>
    let isShared = Mutex(false)

    init(task: Task<AccessToken?, Never>) {
        self.task = task
    }
}

/// 設定で上書きした、使えない設定ディレクトリ。
private struct UnusableConfigDirectory: Error {
    let hostsFile: URL
}
