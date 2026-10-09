import Foundation

/// スレッドをブラウザで開くときの URL。API の URL はそのまま使わず、Web ベース URL に検証済みの値を足して組み立てる。
enum ThreadWebURL {
    /// 組み立てた URL。`https` でホストがアカウントのホストと一致しなければ nil（開かない）。
    static func make(for thread: NotificationThread, endpoints: APIEndpoints) -> URL? {
        var url = repositoryBase(thread.repository, endpoints: endpoints)
        if let suffix = suffix(for: thread, endpoints: endpoints) {
            url = suffix.reduce(url) { $0.appending(path: $1) }
        }
        return isOpenable(url, host: endpoints.host) ? url : nil
    }

    /// リポジトリのページの URL。`https` でホストがアカウントのホストと一致しなければ nil（開かない）。
    static func repositoryPage(_ repository: RepositoryName, endpoints: APIEndpoints) -> URL? {
        let url = repositoryBase(repository, endpoints: endpoints)
        return isOpenable(url, host: endpoints.host) ? url : nil
    }

    private static func repositoryBase(_ repository: RepositoryName, endpoints: APIEndpoints) -> URL {
        endpoints.webBaseURL.appending(path: repository.owner).appending(path: repository.name)
    }

    /// ブラウザで開いてよい URL か。`https` で、ホストが `host`（小文字）と一致し、ポートもユーザー情報も含まないときだけ true。
    static func isOpenable(_ url: URL, host: String) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.scheme?.lowercased() == "https" && components.host?.lowercased() == host
            && components.port == nil && components.user == nil && components.password == nil
    }

    /// リポジトリのページより後ろのパスの要素。組み立てられなければ nil（リポジトリのページを開く）。
    private static func suffix(for thread: NotificationThread, endpoints: APIEndpoints) -> [String]? {
        switch thread.kind {
        case .release: return ["releases"]
        case .discussion: return ["discussions"]
        default: break
        }
        guard let subjectURL = thread.subjectURL,
            let components = endpoints.pathComponentsBelowAPIBase(subjectURL),
            components.count == 5, components[0] == "repos",
            let repository = RepositoryName(owner: components[1], name: components[2]),
            repository.matches(thread.repository)
        else { return nil }
        let id = components[4]
        switch components[3] {
        case "pulls" where ThreadID.isValid(id): return ["pull", id]
        case "issues" where ThreadID.isValid(id): return ["issues", id]
        case "commits" where isCommitSHA(id): return ["commit", id]
        default: return nil
        }
    }

    private static func isCommitSHA(_ text: String) -> Bool {
        (7...40).contains(text.count) && text.allSatisfy { $0.isASCII && $0.isHexDigit }
    }
}
