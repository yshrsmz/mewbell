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
    case ghOutdated(version: GhVersion?)
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
    func reload(update: @escaping @Sendable (DiscoveryState) async -> Void) async
    func discardAllCredentials() async
}

actor AccountDiscovery: AccountDiscovering {
    private static let logger = Logger(subsystem: "com.codingfeline.mewbell", category: "Accounts")

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

    func reload(update: @escaping @Sendable (DiscoveryState) async -> Void) async {
        let state = await discover(update: update)
        // アカウントを使えない状態になったら、持っているトークンをすべて捨てる
        if !state.hasAccounts {
            await credentials.removeAll()
        }
        await update(state)
    }

    func discardAllCredentials() async {
        await credentials.removeAll()
    }

    private func discover(update: @Sendable (DiscoveryState) async -> Void) async -> DiscoveryState {
        guard let ghPath = await locator.locate(overridePath: overridePath()) else {
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
            guard let version, version.isSupported else { return .ghOutdated(version: version) }
            verifiedGhPath = ghPath
        }

        let accounts = hostsFile.map(Account.accounts(from:)) ?? []
        guard !accounts.isEmpty else { return .notLoggedIn }

        await credentials.retainOnly(Set(accounts.map(\.id)))
        var statuses: [AccountID: TokenState] = [:]
        for account in accounts {
            statuses[account.id] = await credentials.contains(account.id) ? .ready : .fetching
        }
        let pending = accounts.filter { statuses[$0.id] == .fetching }
        if !pending.isEmpty {
            await update(
                .accounts(accounts.map { AccountStatus(account: $0, tokenState: statuses[$0.id] ?? .fetching) }))
        }

        let fetched = await fetchTokens(for: pending, using: client)
        for (id, token) in fetched {
            if let token {
                await credentials.set(token, for: id)
                statuses[id] = .ready
            } else {
                statuses[id] = .unavailable
            }
        }
        return .accounts(accounts.map { AccountStatus(account: $0, tokenState: statuses[$0.id] ?? .unavailable) })
    }

    /// アカウントごとの `gh auth token` を並べて実行する。
    private func fetchTokens(for accounts: [Account], using client: GhClient) async -> [(AccountID, AccessToken?)] {
        await withTaskGroup(of: (AccountID, AccessToken?).self) { group in
            for account in accounts {
                group.addTask { (account.id, await client.token(host: account.host, user: account.user)) }
            }
            var results: [(AccountID, AccessToken?)] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }
}
