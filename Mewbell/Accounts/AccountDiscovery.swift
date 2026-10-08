import Foundation
import Synchronization
import os

/// アカウントごとのトークンの状態。
enum TokenState: Sendable, Equatable {
    case fetching
    case ready
    case unavailable
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
}

/// gh の検出からトークンの取得までを行う。`AccountStore` から差し替えられるようにプロトコルにする。
protocol AccountDiscovering: Sendable {
    /// 読み直し、途中と最後の状態を `update` に渡す。
    /// `userInitiated` はユーザーが再読み込みを押したとき true（見つかっていない gh をログインシェルで探し直す）。
    func reload(userInitiated: Bool, update: @escaping @Sendable (DiscoveryState) async -> Void) async
    /// トークンをすべて捨て、以後は受け取らない（アプリの終了時）。
    func closeCredentials() async
}

actor AccountDiscovery: AccountDiscovering, TokenProviding {
    private static let logger = Logger(category: "Accounts")

    private let locator: GhLocator
    private let runner: any ProcessRunning
    private let environment: [String: String]
    private let configDirectory: URL
    private let credentials: CredentialStore
    private let overridePath: @Sendable () -> String?
    /// `gh --version` で対応を確かめた gh の実体のパス
    private var verifiedGhPath: URL?
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
        credentials: CredentialStore,
        overridePath: @escaping @Sendable () -> String? = { nil }
    ) {
        self.locator = locator
        self.runner = runner
        self.environment = environment
        self.configDirectory = configDirectory
        self.credentials = credentials
        self.overridePath = overridePath
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

    func reload(userInitiated: Bool, update: @escaping @Sendable (DiscoveryState) async -> Void) async {
        let state = await discover(userInitiated: userInitiated, update: update)
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
        let client = GhClient(executable: ghPath, runner: runner, environment: environment)
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
        userInitiated: Bool, update: @Sendable (DiscoveryState) async -> Void
    ) async -> DiscoveryState {
        guard let ghPath = await locator.locate(overridePath: overridePath(), retryLoginShell: userInitiated) else {
            verifiedGhPath = nil
            return .ghNotFound
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

        knownAccountIDs = Set(accounts.map(\.id))
        let held = await credentials.retainOnly(knownAccountIDs)
        let pending = accounts.filter { !held.contains($0.id) }
        if !pending.isEmpty {
            await update(
                .accounts(
                    accounts.map { AccountStatus(account: $0, tokenState: held.contains($0.id) ? .ready : .fetching) }))
        }

        let failed = await fetchTokens(for: pending, using: client)
        return .accounts(
            accounts.map { AccountStatus(account: $0, tokenState: failed.contains($0.id) ? .unavailable : .ready) })
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
