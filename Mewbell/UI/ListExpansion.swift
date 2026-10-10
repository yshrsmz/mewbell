import Observation

/// 1 アカウントの区画の折りたたみの状態（アカウントの見出しと、リポジトリのグループ）。
/// アカウントごとに分ける理由は `ListExpansion` を参照。
@MainActor
@Observable
final class AccountExpansion {
    private(set) var isCollapsed = false
    private var collapsedRepositories: Set<RepositoryName> = []

    func isRepositoryCollapsed(_ repository: RepositoryName) -> Bool {
        collapsedRepositories.contains(repository)
    }

    /// 必ず変わるので、そのまま書き込む。
    func toggle() {
        isCollapsed.toggle()
    }

    /// 必ず変わるので、そのまま書き込む。
    func toggleRepository(_ repository: RepositoryName) {
        collapsedRepositories.toggle(repository)
    }

    /// このアカウントと、新着を含むリポジトリを開く。ほかのリポジトリは変えない。
    /// 中身が変わるときだけ書き込む（書き込むだけで、読んでいる View が描き直されるため）。
    func expand(repositories: Set<RepositoryName>) {
        if isCollapsed {
            isCollapsed = false
        }
        if !collapsedRepositories.isDisjoint(with: repositories) {
            collapsedRepositories.subtract(repositories)
        }
    }
}

/// 一覧の折りたたみの状態。起動している間だけメモリに持ち、ディスクには書かない（再起動ですべて開く）。
/// ポップオーバーを閉じても残るように、View ではなくアプリが 1 つだけ持つ。
/// 状態の粒度を読む View の粒度に合わせる: 各区画は自分のアカウントの `AccountExpansion` だけを読むので、
/// 開閉や新着で描き直されるのはその区画だけになる。そのためこの型は `@Observable` にせず、観測されるのは
/// 各 `AccountExpansion` だけにする。
@MainActor
final class ListExpansion {
    private var accounts: [AccountID: AccountExpansion] = [:]

    /// アカウントの状態。無ければ（すべて開いた状態で）作る。
    /// 描画の中から呼ばれるが、この辞書は観測されないので、ここで書き込んでもほかの View の描き直しは起きない。
    func state(for account: AccountID) -> AccountExpansion {
        if let state = accounts[account] {
            return state
        }
        let state = AccountExpansion()
        accounts[account] = state
        return state
    }

    /// 新着が届いたアカウントと、新着を含むリポジトリを開く。
    /// まだ作られていないアカウントは何も畳んでいないので、何もしない。
    func expand(account: AccountID, newThreads: [NotificationThread]) {
        accounts[account]?.expand(repositories: Set(newThreads.map(\.repository)))
    }

    /// `accounts` 以外のアカウントの状態を捨てる（一覧から消えた、無効にした）。
    func retain(_ accounts: Set<AccountID>) {
        self.accounts = self.accounts.filter { accounts.contains($0.key) }
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
