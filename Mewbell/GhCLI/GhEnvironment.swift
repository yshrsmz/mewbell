import Foundation

/// gh（とログインシェル）の子プロセスに渡す環境変数を作る。
enum GhEnvironment {
    /// 残っていると、`gh auth token` が `--hostname` / `--user` で指定したアカウント以外のトークンを返す
    static let removedKeys: Set<String> = [
        "GH_TOKEN",
        "GITHUB_TOKEN",
        "GH_ENTERPRISE_TOKEN",
        "GITHUB_ENTERPRISE_TOKEN",
        "GH_HOST",
    ]

    /// 対話の確認・更新の案内・色付けを止める
    static let addedValues: [String: String] = [
        "GH_PROMPT_DISABLED": "1",
        "GH_NO_UPDATE_NOTIFIER": "1",
        "NO_COLOR": "1",
    ]

    /// `HOME` や `GH_CONFIG_DIR` などそれ以外の変数は残す（gh が設定ディレクトリや Keychain を見つけるのに要る）。
    /// `configDirectory` があれば（設定で上書きしたとき）、`GH_CONFIG_DIR` をそのパスにする。
    static func make(from base: [String: String], configDirectory: URL? = nil) -> [String: String] {
        var environment = base.filter { !removedKeys.contains($0.key) }.merging(addedValues) { _, added in added }
        if let configDirectory {
            environment["GH_CONFIG_DIR"] = configDirectory.path
        }
        return environment
    }
}
