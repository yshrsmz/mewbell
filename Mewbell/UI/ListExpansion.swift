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
    // 変わらないときは書き込まない（書き込むだけで、読んでいる View がすべて描き直される）
    private var collapsedAccounts: Set<AccountID> = []
    private var collapsedRepositories: Set<RepositoryKey> = []

    func isCollapsed(_ account: AccountID) -> Bool {
        collapsedAccounts.contains(account)
    }

    func isCollapsed(_ repository: RepositoryKey) -> Bool {
        collapsedRepositories.contains(repository)
    }

    func toggle(_ account: AccountID) {
        collapsedAccounts.toggle(account)
    }

    func toggle(_ repository: RepositoryKey) {
        collapsedRepositories.toggle(repository)
    }

    /// 新着が届いたアカウントと、新着を含むリポジトリを開く。ほかのリポジトリは変えない。
    func expand(account: AccountID, repositories: Set<RepositoryName>) {
        if collapsedAccounts.contains(account) {
            collapsedAccounts.remove(account)
        }
        let keys = repositories.map { RepositoryKey(account: account, repository: $0) }
        if !collapsedRepositories.isDisjoint(with: keys) {
            collapsedRepositories.subtract(keys)
        }
    }

    /// `accounts` 以外のアカウントの状態を捨てる（一覧から消えた、無効にした）。
    func retain(_ accounts: Set<AccountID>) {
        if !collapsedAccounts.isSubset(of: accounts) {
            collapsedAccounts.formIntersection(accounts)
        }
        if collapsedRepositories.contains(where: { !accounts.contains($0.account) }) {
            collapsedRepositories = collapsedRepositories.filter { accounts.contains($0.account) }
        }
    }
}

extension Set {
    /// 入っていれば外し、無ければ入れる。
    fileprivate mutating func toggle(_ member: Element) {
        if remove(member) == nil {
            insert(member)
        }
    }
}
