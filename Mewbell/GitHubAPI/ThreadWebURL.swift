import Foundation

/// スレッドをブラウザで開くときの URL。API の URL はそのまま使わず、Web ベース URL に検証済みの値を足して組み立てる。
enum ThreadWebURL {
    /// 組み立てた URL。`https` でホストがアカウントのホストと一致しなければ nil（開かない）。
    static func make(for thread: NotificationThread, endpoints: APIEndpoints) -> URL? {
        url(for: thread, target: target(for: thread, endpoints: endpoints), endpoints: endpoints)
    }

    /// Issue・Pull request の番号。`make` と同じ `subject.url` の検証（API ベース URL の下にあること、リポジトリの一致、
    /// 番号の形）を通った Pull request と Issue の番号だけを返す。開く URL を組み立てられない（`make` が nil の）ときも nil。
    static func subjectNumber(for thread: NotificationThread, endpoints: APIEndpoints) -> String? {
        let target = target(for: thread, endpoints: endpoints)
        guard url(for: thread, target: target, endpoints: endpoints) != nil else { return nil }
        switch target {
        case .pullRequest(let id), .issue(let id): return id
        case .commit, .releases, .discussions, nil: return nil
        }
    }

    /// `target` から組み立てた URL。`target` が nil ならリポジトリのページ。開けなければ nil。
    private static func url(for thread: NotificationThread, target: Target?, endpoints: APIEndpoints) -> URL? {
        var url = repositoryBase(thread.repository, endpoints: endpoints)
        if let target {
            url = target.pathComponents.reduce(url) { $0.appending(path: $1) }
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

    /// リポジトリのページより後ろに足すページ。
    private enum Target {
        case pullRequest(String)
        case issue(String)
        case commit(String)
        case releases
        case discussions

        /// リポジトリのページより後ろのパスの要素。
        var pathComponents: [String] {
            switch self {
            case .pullRequest(let id): ["pull", id]
            case .issue(let id): ["issues", id]
            case .commit(let id): ["commit", id]
            case .releases: ["releases"]
            case .discussions: ["discussions"]
            }
        }
    }

    /// リポジトリのページより後ろに足すページ。組み立てられなければ nil（リポジトリのページを開く）。
    private static func target(for thread: NotificationThread, endpoints: APIEndpoints) -> Target? {
        switch thread.kind {
        case .release: return .releases
        case .discussion: return .discussions
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
        case "pulls" where ThreadID.isValid(id): return .pullRequest(id)
        case "issues" where ThreadID.isValid(id): return .issue(id)
        case "commits" where isCommitSHA(id): return .commit(id)
        default: return nil
        }
    }

    private static func isCommitSHA(_ text: String) -> Bool {
        (7...40).contains(text.count) && text.allSatisfy { $0.isASCII && $0.isHexDigit }
    }
}
