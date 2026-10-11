/// 案内に出すコマンド（gh と、gh を入れる Homebrew のコマンド）。ホスト名とユーザー名は `AccountID` から埋め込む
enum GhCommand {
    /// gh を入れるコマンド
    static let install = "brew install gh"
    /// gh を新しくするコマンド
    static let upgrade = "brew upgrade gh"
    /// gh が動くかを確かめるコマンド
    static let version = "gh --version"
    /// gh のログインの状態を確かめるコマンド
    static let status = "gh auth status"
    /// gh にログインするコマンド
    static let login = "gh auth login"
    /// そのアカウントのホストに gh でログインし直すコマンド
    static func relogin(for account: AccountID) -> String {
        "gh auth login --hostname \(account.host)"
    }
    /// そのアカウントをホストのアクティブなアカウントにするコマンド
    static func switchUser(to account: AccountID) -> String {
        "gh auth switch --hostname \(account.host) --user \(account.user)"
    }
    /// そのアカウントのホストのトークンに repo のスコープを足すコマンド
    static func refreshScopes(for account: AccountID) -> String {
        "gh auth refresh --hostname \(account.host) --scopes repo"
    }
}
