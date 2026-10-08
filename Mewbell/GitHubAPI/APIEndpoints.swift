import Foundation

/// アカウントのホストから導いた API と Web のベース URL。トークンを送ってよい相手はこの API ベースだけ。
struct APIEndpoints: Sendable, Equatable {
    /// 小文字の検証済みホスト名
    let host: String
    /// `https://api.github.com`、`https://api.<host>`、`https://<host>/api/v3`
    let apiBaseURL: URL
    /// `https://<host>`
    let webBaseURL: URL

    /// `host` は `GhIdentifier.isValidHost` を通った値を渡す。URL を作れないときは nil。
    init?(host: String) {
        let host = host.lowercased()
        guard GhIdentifier.isValidHost(host) else { return nil }
        let apiBase: String =
            switch HostKind(host: host) {
            case .gitHubDotCom: "https://api.github.com"
            case .gheCloud: "https://api.\(host)"
            case .enterpriseServer: "https://\(host)/api/v3"
            }
        guard let apiBaseURL = URL(string: apiBase), let webBaseURL = URL(string: "https://\(host)") else {
            return nil
        }
        self.host = host
        self.apiBaseURL = apiBaseURL
        self.webBaseURL = webBaseURL
    }

    /// API ベースの下のパス（`notifications` など）の URL。
    func apiURL(path: String) -> URL {
        apiBaseURL.appending(path: path)
    }

    /// トークンを付けて送ってよい URL か。スキームが `https`、ホストとポートが API ベースと一致し、
    /// ユーザー情報を含まず、パスが API ベースのパスの下にあるときだけ true。
    func isAllowedRequestURL(_ url: URL) -> Bool {
        pathComponentsBelowAPIBase(url) != nil
    }

    /// API ベースのパスより後ろのパスの要素。トークンを付けて送ってよい URL でなければ nil。
    func pathComponentsBelowAPIBase(_ url: URL) -> [String]? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let base = URLComponents(url: apiBaseURL, resolvingAgainstBaseURL: false)
        else { return nil }
        guard components.scheme?.lowercased() == "https",
            components.host?.lowercased() == base.host?.lowercased(),
            components.port == nil || components.port == 443,
            components.user == nil, components.password == nil
        else { return nil }
        let path = components.percentEncodedPath
        let basePath = base.percentEncodedPath
        guard !path.split(separator: "/").contains(where: { $0 == ".." || $0 == "." }) else { return nil }
        guard basePath.isEmpty || path == basePath || path.hasPrefix(basePath + "/") else { return nil }
        return path.dropFirst(basePath.count).split(separator: "/").map(String.init)
    }
}
