import Observation

/// アカウントとリポジトリの組。リポジトリのグループの折りたたみを覚えるときの鍵。
struct RepositoryKey: Hashable, Sendable {
    let account: AccountID
    let repository: RepositoryName
}

/// 一覧の折りたたみの状態。起動している間だけメモリに持ち、ディスクには書かない（再起動ですべて開く）。
/// ポップオーバーを閉じても残るように、View ではなくアプリが 1 つだけ持つ。
@MainActor
@Observable
final class ListExpansion {
    private(set) var collapsedAccounts: Set<AccountID> = []
    private(set) var collapsedRepositories: Set<RepositoryKey> = []

    func isCollapsed(_ account: AccountID) -> Bool {
        collapsedAccounts.contains(account)
    }

    func isCollapsed(_ repository: RepositoryKey) -> Bool {
        collapsedRepositories.contains(repository)
    }

    func toggle(_ account: AccountID) {
        if collapsedAccounts.remove(account) == nil {
            collapsedAccounts.insert(account)
        }
    }

    func toggle(_ repository: RepositoryKey) {
        if collapsedRepositories.remove(repository) == nil {
            collapsedRepositories.insert(repository)
        }
    }

    /// 新着が届いたアカウントと、新着を含むリポジトリを開く。ほかのリポジトリは変えない。
    func expand(account: AccountID, repositories: Set<RepositoryName>) {
        collapsedAccounts.remove(account)
        for repository in repositories {
            collapsedRepositories.remove(RepositoryKey(account: account, repository: repository))
        }
    }

    /// `accounts` 以外のアカウントの状態を捨てる（一覧から消えた、無効にした）。
    func retain(_ accounts: Set<AccountID>) {
        collapsedAccounts.formIntersection(accounts)
        collapsedRepositories = collapsedRepositories.filter { accounts.contains($0.account) }
    }
}
