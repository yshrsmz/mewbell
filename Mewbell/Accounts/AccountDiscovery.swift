import Foundation
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
    /// `version` は読み取れたときだけ入る
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

actor AccountDiscovery: AccountDiscovering {
    private static let logger = Logger(category: "Accounts")

    private let locator: GhLocator
    private let runner: any ProcessRunning
    private let environment: [String: String]
    private let configDirectory: URL
    private let credentials: CredentialStore
    private let overridePath: @Sendable () -> String?
    /// `gh --version` で対応を確かめた gh の実体のパス
    private var verifiedGhPath: URL?

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
            await credentials.removeAll()
        }
        await update(state)
    }

    func closeCredentials() async {
        await credentials.close()
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

        let held = await credentials.retainOnly(Set(accounts.map(\.id)))
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
        let fetched = await withTaskGroup(of: (AccountID, AccessToken?).self) { group in
            for account in accounts {
                group.addTask { (account.id, await client.token(host: account.host, user: account.user)) }
            }
            var results: [(AccountID, AccessToken?)] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
        var failed: Set<AccountID> = []
        for (id, token) in fetched {
            if let token {
                await credentials.set(token, for: id)
            } else {
                failed.insert(id)
            }
        }
        return failed
    }
}
