import Foundation

/// スレッドの件名の状態とイベントの取得の結果。
enum ThreadDetailsFetchResult: Sendable, Equatable {
    case found(ThreadDetails)
    /// 番号もリリースの ID も run の探し方も持たない、`404` / `410` / レート制限でない `403` / `422`、検証を通らないタグ、決まらない run
    /// （その `updated_at` の間は取り直さない）
    case unavailable
    /// 401
    case unauthorized
    /// レート制限の 403 / 429（`retryAt` まで待つ）
    case rateLimited(retryAt: Date)
    /// そのほかの状態コード、リダイレクト、通信の失敗、送らなかった、形の崩れたボディ（次の機会に取り直す）
    case failed(FetchFailure)
}

/// 状態とイベントの取得を途中で終えるときの結果（`Result` の失敗の側に載せるための入れ物）。
private struct DetailsStop: Error {
    let result: ThreadDetailsFetchResult

    init(_ result: ThreadDetailsFetchResult) {
        self.result = result
    }
}

// スレッドの件名の状態とイベントの取得（github-api「スレッドのイベントの取得のリクエスト」）
extension GitHubAPIClient {
    /// Timeline の 1 ページの件数
    private static let timelinePerPage = 100

    /// スレッドの件名の状態とイベントを取る（`GET /repos/{owner}/{repo}/issues/{number}` と、その `timeline` の
    /// 1 ページ目、最後のページ、その前のページ）。リリースの ID を持つ Release のスレッドは、代わりにタグを取る
    /// （`GET /repos/{owner}/{repo}/releases/{id}`）。URL は `subject.url` ではなく検証済みのリポジトリ名と番号・ID から
    /// 組み立てる。番号もリリースの ID も run の探し方も持たないスレッドには何も送らない。
    func fetchDetails(
        for thread: NotificationThread, endpoints: APIEndpoints, token: AccessToken
    ) async -> ThreadDetailsFetchResult {
        switch thread.detailsSubject {
        case .number(let number):
            return await fetchIssueDetails(number, of: thread, endpoints: endpoints, token: token)
        case .release(let id):
            return await fetchReleaseTag(id, of: thread.repository, endpoints: endpoints, token: token)
        case .waitingWorkflowRun:
            return await fetchApprovalRequestRun(
                updatedAt: thread.updatedAt, of: thread.repository, endpoints: endpoints, token: token)
        case .checkSuite(let title):
            return await fetchCheckSuiteRun(
                title, updatedAt: thread.updatedAt, of: thread.repository, endpoints: endpoints, token: token)
        case nil: return .unavailable
        }
    }

    /// Issue・Pull request の状態とイベントを取る。
    private func fetchIssueDetails(
        _ number: String, of thread: NotificationThread, endpoints: APIEndpoints, token: AccessToken
    ) async -> ThreadDetailsFetchResult {
        guard ThreadID.isValid(number) else { return .unavailable }
        let issuePath = "repos/\(thread.repository.owner)/\(thread.repository.name)/issues/\(number)"
        let issue: IssueSummary
        switch await get(endpoints.apiURL(path: issuePath), endpoints: endpoints, token: token) {
        case .success(let response):
            guard let decoded = IssueSummary.decode(from: response.body) else { return .failed(.malformedBody) }
            issue = decoded
        case .failure(let stop):
            return stop.result
        }
        let state = issue.subjectState

        let timeline: [TimelineItem]
        switch await fetchTimeline(
            path: issuePath + "/timeline", updatedAt: thread.updatedAt, endpoints: endpoints, token: token
        )
        {
        case .success(let items): timeline = items
        case .failure(let stop) where stop.result == .unavailable:
            return .found(ThreadDetails(state: state, event: nil))
        case .failure(let stop): return stop.result
        }
        return .found(
            ThreadDetails(
                state: state,
                event: ThreadEventResolver.event(issue: issue, timeline: timeline, updatedAt: thread.updatedAt)))
    }

    /// リリースのタグを取る（github-api「リリースのタグの取得のリクエスト」「リリースのタグの取得の tag_name」）。
    /// 読むのは `tag_name` だけで、検証を通らなければタグは「無い」。
    private func fetchReleaseTag(
        _ releaseID: String, of repository: RepositoryName, endpoints: APIEndpoints, token: AccessToken
    ) async -> ThreadDetailsFetchResult {
        guard ThreadID.isValid(releaseID) else { return .unavailable }
        let path = "repos/\(repository.owner)/\(repository.name)/releases/\(releaseID)"
        switch await get(endpoints.apiURL(path: path), endpoints: endpoints, token: token) {
        case .success(let response):
            guard let release = ReleaseSummary.decode(from: response.body) else { return .failed(.malformedBody) }
            guard ThreadWebURL.releaseTagComponents(release.tagName) != nil else { return .unavailable }
            return .found(ThreadDetails(state: nil, event: nil, resource: .release(tag: release.tagName)))
        case .failure(let stop):
            return stop.result
        }
    }

    /// 承認を待っている run を、`pending_deployments` で確かめる上限（これより多ければ決めない）
    private static let waitingRunLimit = 5

    /// 種類が WorkflowRun のスレッドの run を探す
    /// （github-api の「ワークフローの実行の検索の」で始まる要件のうち WorkflowRun のもの）。通知の前後に承認を
    /// 待ち始めた run があれば、その中から決める（通知の run がまだ待っているかもしれないので、決まらなくても別の探し方は
    /// しない）。無ければ、通知の時刻に動いていた run を探す。どちらでも決まらなければ「無い」。
    private func fetchApprovalRequestRun(
        updatedAt: Date, of repository: RepositoryName, endpoints: APIEndpoints, token: AccessToken
    ) async -> ThreadDetailsFetchResult {
        switch await fetchRuns(
            of: repository, query: [("status", "waiting"), ("per_page", "6")], endpoints: endpoints, token: token)
        {
        // 承認を待っている run をすべて見られて、そのどれも通知の前後に待ち始めていなければ（0 件を含む）、通知の run は
        // もう承認されたものとして、通知の時刻に動いていた run を探す。一覧が「無い」ときも同じ
        case .success(let page)
        where page.totalCount <= page.workflowRuns.count
            && !WorkflowRunSummary.hasRun(updatedNear: updatedAt, in: page.workflowRuns):
            return await fetchRunSpanning(updatedAt, of: repository, endpoints: endpoints, token: token)
        case .failure(let stop) where stop.result == .unavailable:
            return await fetchRunSpanning(updatedAt, of: repository, endpoints: endpoints, token: token)
        case .success(let page):
            return await approvableWaitingRun(
                in: page, updatedAt: updatedAt, of: repository, endpoints: endpoints, token: token)
        case .failure(let stop):
            return stop.result
        }
    }

    /// 承認を待っている run の一覧 `page`（1〜5 件）のうち、ユーザーが承認できる待ちを持ち、承認待ちになった時刻（`updated_at`）が
    /// `updatedAt`（通知の時刻）に最も近いもの（1 件でも確かめる。通知の run が承認された後に、別の人の承認を待つ run や
    /// 後から待ち始めた run を開かないように）。決まらなければ「無い」。
    private func approvableWaitingRun(
        in page: WorkflowRunsPage, updatedAt: Date, of repository: RepositoryName, endpoints: APIEndpoints,
        token: AccessToken
    ) async -> ThreadDetailsFetchResult {
        let runsPath = Self.runsPath(of: repository)
        let runs = page.workflowRuns
        guard max(page.totalCount, runs.count) <= Self.waitingRunLimit, !runs.isEmpty,
            runs.allSatisfy({ $0.validatedID != nil })
        else { return .unavailable }
        switch await approvableRuns(runs, runsPath: runsPath, endpoints: endpoints, token: token) {
        case .success(let approvable):
            // 通知の run が承認された後に待ち始めた別の run を選ばないように、承認待ちになった時刻（run の
            // `updated_at`）が通知に最も近いものにする
            return Self.workflowRunResult(WorkflowRunSummary.closestRun(updatedNear: updatedAt, in: approvable))
        case .failure(let stop):
            return stop.result
        }
    }

    /// `runs`（ID が検証を通ったもの）のうち、ユーザーが承認できる待ちを持つものを、`pending_deployments` を順に取って
    /// 求める。見られない run は承認できないものとして数え、ほかの失敗があればそこで止める。
    private func approvableRuns(
        _ runs: [WorkflowRunSummary], runsPath: String, endpoints: APIEndpoints, token: AccessToken
    ) async -> Result<[WorkflowRunSummary], DetailsStop> {
        var approvable: [WorkflowRunSummary] = []
        for run in runs {
            guard let id = run.validatedID else { continue }
            let pendingURL = endpoints.apiURL(path: "\(runsPath)/\(id)/pending_deployments")
            switch await get(pendingURL, endpoints: endpoints, token: token) {
            case .success(let response):
                guard let deployments = PendingDeployment.decodeList(from: response.body) else {
                    return .failure(DetailsStop(.failed(.malformedBody)))
                }
                if deployments.contains(where: \.currentUserCanApprove) { approvable.append(run) }
            case .failure(let stop) where stop.result == .unavailable:
                continue
            case .failure(let stop):
                return .failure(stop)
            }
        }
        return .success(approvable)
    }

    /// `date`（通知の時刻）より前に作られた run のうち、承認を待っていなくて、`date` に動いていた run が 1 件だけなら、その run。
    private func fetchRunSpanning(
        _ date: Date, of repository: RepositoryName, endpoints: APIEndpoints, token: AccessToken
    ) async -> ThreadDetailsFetchResult {
        let createdBefore = "<=" + date.formatted(Self.apiDateFormat)
        switch await fetchRuns(
            of: repository, query: [("created", createdBefore), ("per_page", "30")], endpoints: endpoints,
            token: token)
        {
        case .success(let page):
            // 承認を待っている run は、承認できるかと時刻をもう調べて外したものなので数えない
            let runs = page.workflowRuns.filter { $0.status != "waiting" }
            return Self.workflowRunResult(WorkflowRunSummary.runSpanning(date, in: runs))
        case .failure(let stop):
            return stop.result
        }
    }

    /// 種類が CheckSuite のスレッドの run を、件名のブランチの run の一覧から探す
    /// （github-api「ワークフローの実行の検索の CheckSuite の件名」「ワークフローの実行の検索の CheckSuite の run」）。
    /// ワークフロー名と結果が一致し、`updated_at` がスレッドに最も近い run。決まらなければ「無い」。
    private func fetchCheckSuiteRun(
        _ title: CheckSuiteTitle, updatedAt: Date, of repository: RepositoryName, endpoints: APIEndpoints,
        token: AccessToken
    ) async -> ThreadDetailsFetchResult {
        switch await fetchRuns(
            of: repository, query: [("branch", title.branch), ("per_page", "30")], endpoints: endpoints, token: token)
        {
        case .success(let page):
            let runs = page.workflowRuns.filter {
                $0.name == title.workflowName && $0.conclusion == title.result.conclusion
            }
            return Self.workflowRunResult(WorkflowRunSummary.closestRun(updatedNear: updatedAt, in: runs))
        case .failure(let stop):
            return stop.result
        }
    }

    /// 選んだ run があればその run を開く詳細、無ければ「無い」。
    private static func workflowRunResult(_ id: String?) -> ThreadDetailsFetchResult {
        id.map { .found(ThreadDetails(state: nil, event: nil, resource: .workflowRun(id: $0))) } ?? .unavailable
    }

    /// `repos/<owner>/<name>/actions/runs`
    private static func runsPath(of repository: RepositoryName) -> String {
        "repos/\(repository.owner)/\(repository.name)/actions/runs"
    }

    /// run の一覧を `query` で絞って取る。
    private func fetchRuns(
        of repository: RepositoryName, query: [(name: String, value: String)], endpoints: APIEndpoints,
        token: AccessToken
    ) async -> Result<WorkflowRunsPage, DetailsStop> {
        let url = query.reduce(endpoints.apiURL(path: Self.runsPath(of: repository))) {
            $0.appending(queryValue: $1.value, for: $1.name)
        }
        switch await get(url, endpoints: endpoints, token: token) {
        case .success(let response):
            guard let page = WorkflowRunsPage.decode(from: response.body) else {
                return .failure(DetailsStop(.failed(.malformedBody)))
            }
            return .success(page)
        case .failure(let stop):
            return .failure(stop)
        }
    }

    /// Timeline の 1 ページ目と、`rel="last"` があれば最後のページ、最後のページが近さの幅の始まりまで届いていなければ
    /// その前のページを取り、古い順につなげる。その前のページが 1 ページ目なら取り直さない（取るのは最大 3 ページ）。
    private func fetchTimeline(
        path: String, updatedAt: Date, endpoints: APIEndpoints, token: AccessToken
    ) async -> Result<[TimelineItem], DetailsStop> {
        guard let firstURL = Self.timelineURL(endpoints.apiURL(path: path), page: nil) else {
            return .failure(DetailsStop(.failed(.rejectedURL)))
        }
        let first = await getPage(firstURL, endpoints: endpoints, token: token)
        guard case .success(let (firstItems, link)) = first else { return first.map(\.items) }
        // `Link` からはページ番号だけを読み、URL は 1 ページ目から組み立てる（API が返した URL には送らない。
        // プロキシの下の GHES で `Link` が内部のホスト名を指していても取れるように）
        guard let lastPage = LinkHeader.lastURL(in: link).flatMap(Self.page(of:)), lastPage > 1,
            let lastURL = Self.timelineURL(firstURL, page: lastPage)
        else { return .success(firstItems) }
        let last = await getPage(lastURL, endpoints: endpoints, token: token)
        guard case .success(let (lastItems, _)) = last else { return last.map(\.items) }
        // 最後のページが近さの幅の始まりより前まで届いていれば、前のページに近い候補は無い
        guard !ThreadEventResolver.reachesBeforeWindow(lastItems, updatedAt: updatedAt) else {
            return .success(lastItems)
        }
        // その前のページが 1 ページ目なら、取ってある 1 ページ目を使う
        guard lastPage - 1 > 1 else { return .success(firstItems + lastItems) }
        guard let previousURL = Self.timelineURL(firstURL, page: lastPage - 1) else { return .success(lastItems) }
        switch await getPage(previousURL, endpoints: endpoints, token: token) {
        case .success(let previous): return .success(previous.items + lastItems)
        // 取っている間に項目が減ってページが無くなったなど。取ってある最後のページで決める
        case .failure(let stop) where stop.result == .unavailable: return .success(lastItems)
        case .failure(let stop): return .failure(stop)
        }
    }

    /// Timeline の 1 ページを取り、項目と `Link` ヘッダーを返す。
    private func getPage(
        _ url: URL, endpoints: APIEndpoints, token: AccessToken
    ) async -> Result<(items: [TimelineItem], link: String?), DetailsStop> {
        switch await get(url, endpoints: endpoints, token: token) {
        case .success(let response):
            guard let items = TimelineItem.decodePage(from: response.body) else {
                return .failure(DetailsStop(.failed(.malformedBody)))
            }
            return .success((items, response.header("Link")))
        case .failure(let result):
            return .failure(result)
        }
    }

    /// `url` の `per_page` を Timeline の件数にし、`page` があればそのページにした URL。
    private static func timelineURL(_ url: URL, page: Int?) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var items = (components.queryItems ?? []).filter { $0.name != "per_page" && $0.name != "page" }
        items.append(URLQueryItem(name: "per_page", value: String(timelinePerPage)))
        if let page { items.append(URLQueryItem(name: "page", value: String(page))) }
        components.queryItems = items
        return components.url
    }

    /// URL の `page` の値。
    private static func page(of url: URL) -> Int? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first { $0.name == "page" }?.value.flatMap { Int($0) }
    }

    /// 状態とイベントの取得の `GET` を送り、`200` ならレスポンスを、そうでなければ結果を返す。
    private func get(
        _ url: URL, endpoints: APIEndpoints, token: AccessToken
    ) async -> Result<HTTPResponse, DetailsStop> {
        let response: HTTPResponse
        switch await gateway.send(url, method: "GET", endpoints: endpoints, token: token, ifModifiedSince: nil) {
        case .success(let value): response = value
        case .failure(let failure): return .failure(DetailsStop(.failed(failure)))
        }
        switch response.statusCode {
        case 200:
            return .success(response)
        case 401:
            return .failure(DetailsStop(.unauthorized))
        case 403, 429:
            switch rateLimit(response) {
            case .until(let retryAt): return .failure(DetailsStop(.rateLimited(retryAt: retryAt)))
            // 待ち時間が分からなければ今にする（待つ時間は呼び出し元の最短の時間）
            case .unknownWait: return .failure(DetailsStop(.rateLimited(retryAt: now())))
            case nil: return .failure(DetailsStop(.unavailable))
            }
        case 404, 410, 422:
            return .failure(DetailsStop(.unavailable))
        default:
            return .failure(DetailsStop(.failed(.unexpectedStatus(response.statusCode))))
        }
    }
}
