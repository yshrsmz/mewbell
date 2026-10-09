/// 設定で上書きした gh のパスと設定ディレクトリ。読み直しごとに `AccountDiscovery` に渡す。
struct GhOverrides: Sendable, Equatable {
    var executablePath: String?
    var configDirectory: String?
}
