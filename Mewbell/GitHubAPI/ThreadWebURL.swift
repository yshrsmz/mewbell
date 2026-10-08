import Foundation

/// スレッドをブラウザで開くときの URL。API の URL はそのまま使わず、Web ベース URL に検証済みの値を足して組み立てる。
enum ThreadWebURL {
    /// 組み立てた URL。`https` でホストがアカウントのホストと一致しなければ nil（開かない）。
    static func make(for thread: NotificationThread, endpoints: APIEndpoints) -> URL? {
        let repository = thread.repository
        var url = endpoints.webBaseURL.appending(path: repository.owner).appending(path: repository.name)
        if let suffix = suffix(for: thread, endpoints: endpoints) {
            url = suffix.reduce(url) { $0.appending(path: $1) }
        }
        guard url.scheme == "https", url.host()?.lowercased() == endpoints.host else { return nil }
        return url
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
        case "pulls" where isNumber(id): return ["pull", id]
        case "issues" where isNumber(id): return ["issues", id]
        case "commits" where isCommitSHA(id): return ["commit", id]
        default: return nil
        }
    }

    private static func isNumber(_ text: String) -> Bool {
        (1...20).contains(text.count) && text.allSatisfy { $0.isASCII && $0.isNumber }
    }

    private static func isCommitSHA(_ text: String) -> Bool {
        (7...40).contains(text.count) && text.allSatisfy { $0.isASCII && $0.isHexDigit }
    }
}
