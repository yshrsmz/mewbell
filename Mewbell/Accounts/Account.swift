/// アカウントのホストの種類。
enum HostKind: Sendable, Equatable {
    case gitHubDotCom
    case gheCloud
    case enterpriseServer

    init(host: String) {
        let host = host.lowercased()
        if host == "github.com" {
            self = .gitHubDotCom
        } else if host.hasSuffix(".ghe.com") {
            self = .gheCloud
        } else {
            self = .enterpriseServer
        }
    }

    var displayName: String {
        switch self {
        case .gitHubDotCom: "GitHub.com"
        case .gheCloud: "GHE Cloud"
        case .enterpriseServer: "Enterprise Server"
        }
    }
}

/// `<host>/<user>` で表すアカウントの識別子。ホストは小文字にそろえる。
struct AccountID: Hashable, Sendable, CustomStringConvertible {
    let host: String
    let user: String

    init(host: String, user: String) {
        self.host = host.lowercased()
        self.user = user
    }

    /// `hosts.yml` や保存した値など、信頼できない文字列から作る。ホスト名・ユーザー名が検証を通らなければ nil。
    init?(validatingHost host: String, user: String) {
        let host = host.lowercased()
        guard GhIdentifier.isValidHost(host), GhIdentifier.isValidUser(user) else { return nil }
        self.init(host: host, user: user)
    }

    var description: String { "\(host)/\(user)" }

    /// 画面と macOS の通知に出すアカウントの名前（`alice (github.com)`）
    var displayName: String { "\(user) (\(host))" }
}

/// gh にログイン済みのアカウント。
struct Account: Hashable, Sendable, Identifiable {
    let id: AccountID
    /// gh のアクティブなアカウントかどうか
    let isActive: Bool

    var host: String { id.host }
    var user: String { id.user }
    var displayName: String { id.displayName }
    var hostKind: HostKind { HostKind(host: host) }

    /// `hosts.yml` から、表示する順に並べたアカウントを作る。
    /// `github.com` を先頭に残りのホストを名前順に、同じホストではアクティブなユーザーを先頭に残りを名前順に並べる。
    static func accounts(from hostsFile: HostsFile) -> [Account] {
        let hosts = hostsFile.hosts.sorted { lhs, rhs in
            let lhsIsDotCom = HostKind(host: lhs.name) == .gitHubDotCom
            if lhsIsDotCom != (HostKind(host: rhs.name) == .gitHubDotCom) {
                return lhsIsDotCom
            }
            return lhs.name < rhs.name
        }
        return hosts.flatMap { host in
            host.users
                .map { Account(id: AccountID(host: host.name, user: $0), isActive: $0 == host.activeUser) }
                .sorted { lhs, rhs in
                    lhs.isActive != rhs.isActive ? lhs.isActive : lhs.user.lowercased() < rhs.user.lowercased()
                }
        }
    }
}
