/// 案内に出す gh のコマンド。ホスト名とユーザー名は検証済みの `Account` の値を埋め込む
enum GhCommand {
    /// gh が動くかを確かめるコマンド
    static let version = "gh --version"
    /// gh のログインの状態を確かめるコマンド
    static let status = "gh auth status"
    /// gh にログインするコマンド（ホストを決めないとき）
    static let login = "gh auth login"
    /// そのホストに gh でログインし直すコマンド
    static func login(host: String) -> String { "gh auth login --hostname \(host)" }
    /// そのホストのアクティブなアカウントを切り替えるコマンド
    static func switchUser(host: String, user: String) -> String { "gh auth switch --hostname \(host) --user \(user)" }
    /// そのホストのトークンに repo のスコープを足すコマンド
    static func refreshScopes(host: String) -> String { "gh auth refresh --hostname \(host) --scopes repo" }
}
