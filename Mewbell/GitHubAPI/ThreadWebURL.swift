import Foundation

/// スレッドをブラウザで開くときの URL。API の URL はそのまま使わず、Web ベース URL に検証済みの値を足して組み立てる。
enum ThreadWebURL {
    /// 組み立てた URL。`https` でホストがアカウントのホストと一致しなければ nil（開かない）。
    static func make(for thread: NotificationThread, endpoints: APIEndpoints) -> URL? {
        let target = target(
            kind: thread.kind, subjectURL: thread.subjectURL, repository: thread.repository, endpoints: endpoints,
            releaseTag: thread.details?.releaseTag)
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
        case .commit, .discussion, .discussions, .releaseTag, .releases, nil: return nil
        }
    }

    /// Release のリリースの ID。種類が Release で、`subject.url` が `make` と同じ検証（API ベース URL の下にあること、
    /// リポジトリの一致）を通った `releases/<1〜20 桁の数字>` のときだけ返す。リリースのページを開けないときも nil。
    /// スレッドを作る前に求めるので、スレッドではなくその部品を受け取る。
    static func releaseID(
        kind: SubjectKind, subjectURL: URL?, repository: RepositoryName, endpoints: APIEndpoints
    ) -> String? {
        guard case .release = kind,
            let subject = subjectPath(subjectURL, repository: repository, endpoints: endpoints),
            subject.collection == "releases", ThreadID.isValid(subject.id),
            url(repository: repository, target: .releases, endpoints: endpoints) != nil
        else { return nil }
        return subject.id
    }

    /// リリースのタグを、Web の URL のパスに足す要素に分ける。空・255 文字より長い・空白か制御文字を含む・
    /// `/` で区切った要素に空か `.` か `..` があるときは nil（タグとして受け付けない）。
    static func releaseTagComponents(_ tag: String) -> [String]? {
        guard !tag.isEmpty, tag.count <= 255,
            tag.unicodeScalars.allSatisfy({
                !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.controlCharacters.contains($0)
            })
        else { return nil }
        let components = tag.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return nil }
        return components
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
        /// 個別のリリース（タグを `/` で区切った要素）
        case releaseTag([String])
        case releases
        /// 個別のディスカッション（番号）
        case discussion(String)
        case discussions

        /// リポジトリのページより後ろのパスの要素。
        var pathComponents: [String] {
            switch self {
            case .pullRequest(let id): ["pull", id]
            case .issue(let id): ["issues", id]
            case .commit(let id): ["commit", id]
            case .releaseTag(let tag): ["releases", "tag"] + tag
            case .releases: ["releases"]
            case .discussion(let id): ["discussions", id]
            case .discussions: ["discussions"]
            }
        }
    }

    /// リポジトリのページより後ろに足すページ。組み立てられなければ nil（リポジトリのページを開く）。
    /// Release と Discussion は種類で決め、`subject.url` から個別のページを作れなければそれぞれの一覧のページにする。
    private static func target(
        kind: SubjectKind, subjectURL: URL?, repository: RepositoryName, endpoints: APIEndpoints,
        releaseTag: String? = nil
    ) -> Target? {
        let subject = subjectPath(subjectURL, repository: repository, endpoints: endpoints)
        switch kind {
        case .release:
            return releaseTag.flatMap(releaseTagComponents).map(Target.releaseTag) ?? .releases
        case .discussion:
            guard let subject, subject.collection == "discussions", ThreadID.isValid(subject.id) else {
                return .discussions
            }
            return .discussion(subject.id)
        default: break
        }
        guard let subject else { return nil }
        switch subject.collection {
        case "pulls" where ThreadID.isValid(subject.id): return .pullRequest(subject.id)
        case "issues" where ThreadID.isValid(subject.id): return .issue(subject.id)
        case "commits" where isCommitSHA(subject.id): return .commit(subject.id)
        default: return nil
        }
    }

    /// `subject.url` のうち、API ベース URL の下の `repos/<owner>/<name>/<collection>/<id>` で、`<owner>/<name>` が
    /// スレッドのリポジトリと一致するものの `<collection>` と `<id>`。当たらなければ nil。
    private static func subjectPath(
        _ subjectURL: URL?, repository: RepositoryName, endpoints: APIEndpoints
    ) -> (collection: String, id: String)? {
        guard let subjectURL,
            let components = endpoints.pathComponentsBelowAPIBase(subjectURL),
            components.count == 5, components[0] == "repos",
            let subjectRepository = RepositoryName(owner: components[1], name: components[2]),
            subjectRepository.matches(repository)
        else { return nil }
        return (components[3], components[4])
    }

    private static func isCommitSHA(_ text: String) -> Bool {
        (7...40).contains(text.count) && text.allSatisfy { $0.isASCII && $0.isHexDigit }
    }
}
