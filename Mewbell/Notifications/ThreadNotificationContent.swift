import Foundation

/// macOS の通知の中身。トークンと API の URL は入れない。
struct ThreadNotificationContent: Sendable, Equatable {
    /// `<host>/<user>/<threadId>`
    let identifier: String
    let title: String
    let subtitle: String
    let body: String
    /// 通知センターでまとめる単位（`<host>/<user>`）
    let threadIdentifier: String
    let userInfo: [String: String]

    enum Key {
        static let host = "host"
        static let user = "user"
        static let threadID = "threadID"
        static let repository = "repository"
        static let url = "url"
    }

    init(thread: NotificationThread, account: AccountID) {
        identifier = Self.identifier(threadID: thread.id, account: account)
        title = thread.title
        subtitle = thread.repository.description
        body = "\(NotificationGrouping.reasonText(thread.reason)) · \(account.user)@\(account.host)"
        threadIdentifier = account.description
        var userInfo = [
            Key.host: account.host, Key.user: account.user, Key.threadID: thread.id,
            Key.repository: thread.repository.description,
        ]
        if let endpoints = APIEndpoints(host: account.host),
            let url = ThreadWebURL.make(for: thread, endpoints: endpoints)
        {
            userInfo[Key.url] = url.absoluteString
        }
        self.userInfo = userInfo
    }

    static func identifier(threadID: String, account: AccountID) -> String {
        identifierPrefix(of: account) + threadID
    }

    /// そのアカウントの通知の識別子の前置き。ユーザー名は `/` を含まないので、別のアカウントに前方一致しない。
    static func identifierPrefix(of account: AccountID) -> String {
        "\(account)/"
    }
}

/// 通知のクリックから開くスレッド。`userInfo` を検証し直して作る。
struct ThreadOpenRequest: Sendable, Equatable {
    let account: AccountID
    let threadID: String
    /// `https` で、ホストがアカウントのホストと一致する URL
    let url: URL

    /// ホスト名・ユーザー名・スレッド ID のどれかが検証を通らないか、開ける URL を作れなければ nil。
    /// URL が検証を通らなければ、リポジトリのページに置き換える。
    init?(userInfo: [AnyHashable: Any]) {
        typealias Key = ThreadNotificationContent.Key
        guard let host = (userInfo[Key.host] as? String)?.lowercased(), let user = userInfo[Key.user] as? String,
            let threadID = userInfo[Key.threadID] as? String,
            GhIdentifier.isValidHost(host), GhIdentifier.isValidUser(user), ThreadID.isValid(threadID),
            let endpoints = APIEndpoints(host: host)
        else { return nil }
        if let url = (userInfo[Key.url] as? String).flatMap(URL.init(string:)), ThreadWebURL.isOpenable(url, host: host)
        {
            self.url = url
        } else if let repository = (userInfo[Key.repository] as? String).flatMap(RepositoryName.init(fullName:)),
            let url = ThreadWebURL.repositoryPage(repository, endpoints: endpoints)
        {
            self.url = url
        } else {
            return nil
        }
        account = AccountID(host: host, user: user)
        self.threadID = threadID
    }
}
