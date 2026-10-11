import Foundation

/// スレッドをブラウザで開くときの URL。API の URL はそのまま使わず、Web ベース URL に検証済みの値を足して組み立てる。
enum ThreadWebURL {
    /// 組み立てた URL。`https` でホストがアカウントのホストと一致しなければ nil（開かない）。
    static func make(for thread: NotificationThread, endpoints: APIEndpoints) -> URL? {
        let target = target(
            kind: thread.kind, subjectURL: thread.subjectURL, repository: thread.repository, endpoints: endpoints)
        return url(repository: thread.repository, target: target, endpoints: endpoints)
    }

    /// Issue・Pull request の番号。`make` と同じ `subject.url` の検証（API ベース URL の下にあること、リポジトリの一致、
    /// 番号の形）を通った Pull request と Issue の番号だけを返す。開く URL を組み立てられない（`make` が nil の）ときも nil。
    /// スレッドを作る前に求めるので、スレッドではなくその部品を受け取る。
    static func subjectNumber(
        kind: SubjectKind, subjectURL: URL?, repository: RepositoryName, endpoints: APIEndpoints
    ) -> String? {
        let target = target(kind: kind, subjectURL: subjectURL, repository: repository, endpoints: endpoints)
        guard url(repository: repository, target: target, endpoints: endpoints) != nil else { return nil }
        switch target {
        case .pullRequest(let id), .issue(let id): return id
        case .commit, .releases, .discussions, nil: return nil
        }
    }

    /// `target` から組み立てた URL。`target` が nil ならリポジトリのページ。開けなければ nil。
    private static func url(repository: RepositoryName, target: Target?, endpoints: APIEndpoints) -> URL? {
        var url = repositoryBase(repository, endpoints: endpoints)
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

    /// アカウントのホストの Web の通知一覧（`https://<host>/notifications`、絞り込みなし）。開けなければ nil。
    static func notificationsPage(endpoints: APIEndpoints) -> URL? {
        let url = endpoints.webBaseURL.appending(path: "notifications")
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
    private static func target(
        kind: SubjectKind, subjectURL: URL?, repository: RepositoryName, endpoints: APIEndpoints
    ) -> Target? {
        switch kind {
        case .release: return .releases
        case .discussion: return .discussions
        default: break
        }
        guard let subjectURL,
            let components = endpoints.pathComponentsBelowAPIBase(subjectURL),
            components.count == 5, components[0] == "repos",
            let subjectRepository = RepositoryName(owner: components[1], name: components[2]),
            subjectRepository.matches(repository)
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
