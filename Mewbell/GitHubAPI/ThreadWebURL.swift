import Foundation

/// スレッドをブラウザで開くときの URL。API の URL はそのまま使わず、Web ベース URL に検証済みの値を足して組み立てる。
enum ThreadWebURL {
    /// 組み立てた URL。`https` でホストがアカウントのホストと一致しなければ nil（開かない）。
    static func make(for thread: NotificationThread, endpoints: APIEndpoints) -> URL? {
        let subject = subjectPath(thread.subjectURL, repository: thread.repository, endpoints: endpoints)
        let target = target(kind: thread.kind, title: thread.title, subject: subject, details: thread.details)
        return url(repository: thread.repository, target: target, endpoints: endpoints)
    }

    /// 件名の詳細を取りに行く先。`make` と同じ `subject.url` の検証（API ベース URL の下にあること、リポジトリの一致、
    /// 番号・ID の形）を通った、Pull request と Issue の番号か、種類が Release の `releases/<1〜20 桁の数字>` の ID か、
    /// WorkflowRun と CheckSuite（件名を読めるもの）の run の探し方だけを返す。開く URL を組み立てられない（`make` が
    /// nil の）ときも nil。スレッドを作る前に求めるので、スレッドではなくその部品を受け取る。
    static func detailsSubject(
        kind: SubjectKind, title: String, subjectURL: URL?, repository: RepositoryName, endpoints: APIEndpoints
    ) -> DetailsSubject? {
        let subject = subjectPath(subjectURL, repository: repository, endpoints: endpoints)
        let target = target(kind: kind, title: title, subject: subject, details: nil)
        guard url(repository: repository, target: target, endpoints: endpoints) != nil else { return nil }
        switch target {
        case .pullRequest(let id), .issue(let id):
            return .number(id)
        case .releases:
            guard let subject, subject.collection == "releases", ThreadID.isValid(subject.id) else { return nil }
            return .release(id: subject.id)
        case .actions:
            // `actionsTarget` が `.actions` を返すのは WorkflowRun と CheckSuite だけ
            return kind == .workflowRun ? .waitingWorkflowRun : CheckSuiteTitle(title).map(DetailsSubject.checkSuite)
        case .commit, .discussion, .discussions, .releaseTag, .workflowRun, nil:
            return nil
        }
    }

    /// リリースのタグを、Web の URL のパスに足す要素に分ける。空・UTF-8 で 255 バイトより長い・空白か制御文字を含む・
    /// `/` で区切った要素に空か `.` か `..` があるときは nil（タグとして受け付けない）。
    static func releaseTagComponents(_ tag: String) -> [String]? {
        guard !tag.isEmpty, tag.utf8.count <= 255,
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
            if let query = target.query {
                url = url.appending(queryValue: query, for: "query")
            }
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
        /// 個別のワークフローの実行（run の ID）
        case workflowRun(String)
        /// Actions の一覧（`query` があれば、それで絞り込む）
        case actions(query: String?)

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
            case .workflowRun(let id): ["actions", "runs", id]
            case .actions: ["actions"]
            }
        }

        /// パスの後ろに付ける `query` の値。
        var query: String? {
            if case .actions(let query) = self { query } else { nil }
        }
    }

    /// リポジトリのページより後ろに足すページ。組み立てられなければ nil（リポジトリのページを開く）。
    /// Release と Discussion は種類で決め、`subject.url` から個別のページを作れなければそれぞれの一覧のページにする。
    /// WorkflowRun と CheckSuite は、`subject.url` が Pull request・Issue・Commit を指さなければ、覚えた run のページか
    /// Actions の一覧にする。
    /// `subject` は `subjectPath` で読んだ `subject.url`。
    private static func target(
        kind: SubjectKind, title: String, subject: (collection: String, id: String)?, details: ThreadDetails?
    ) -> Target? {
        if case .release = kind {
            return details?.releaseTag.flatMap(releaseTagComponents).map(Target.releaseTag) ?? .releases
        }
        if case .discussion = kind {
            guard let subject, subject.collection == "discussions", ThreadID.isValid(subject.id) else {
                return .discussions
            }
            return .discussion(subject.id)
        }
        return subject.flatMap(subjectPage) ?? actionsTarget(kind: kind, title: title, details: details)
    }

    /// `subject.url` が指す Pull request・Issue・Commit のページ。当たらなければ nil。
    private static func subjectPage(_ subject: (collection: String, id: String)) -> Target? {
        switch subject.collection {
        case "pulls" where ThreadID.isValid(subject.id): .pullRequest(subject.id)
        case "issues" where ThreadID.isValid(subject.id): .issue(subject.id)
        case "commits" where isCommitSHA(subject.id): .commit(subject.id)
        default: nil
        }
    }

    /// WorkflowRun と CheckSuite の、覚えた run のページか Actions の一覧。ほかの種類は nil。
    private static func actionsTarget(kind: SubjectKind, title: String, details: ThreadDetails?) -> Target? {
        let runID = details?.workflowRunID.flatMap { ThreadID.isValid($0) ? $0 : nil }
        switch kind {
        case .workflowRun:
            return runID.map(Target.workflowRun) ?? .actions(query: "is:waiting")
        case .checkSuite:
            return runID.map(Target.workflowRun) ?? .actions(query: CheckSuiteTitle(title).map(actionsFilter))
        default:
            return nil
        }
    }

    /// 種類が CheckSuite の run が決まらないときの、Actions の一覧の絞り込み（ワークフロー名・結果・ブランチの順）。
    /// ワークフロー名が `"` を含むときは、絞り込みの意味が変わらないように名前では絞らない。
    private static func actionsFilter(_ title: CheckSuiteTitle) -> String {
        let status =
            switch title.result {
            case .failed, .failedAtStartup: "failure"
            case .cancelled: "cancelled"
            case .skipped: "skipped"
            case .succeeded: "success"
            }
        let workflow = title.workflowName.contains("\"") ? nil : "workflow:\"\(title.workflowName)\""
        return [workflow, "is:\(status)", "branch:\(title.branch)"].compactMap { $0 }.joined(separator: " ")
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
