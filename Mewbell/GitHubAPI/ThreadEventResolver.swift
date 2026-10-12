import Foundation

/// `GET /repos/{owner}/{repo}/issues/{number}` のうち、状態とイベントを決めるのに使う値だけ。本文などは型に載せない。
struct IssueSummary: Decodable, Sendable {
    struct Login: Decodable, Sendable {
        let login: String?
    }

    struct PullRequest: Decodable, Sendable {
        let mergedAt: String?
    }

    let createdAt: String
    let user: Login?
    let state: String
    let stateReason: String?
    let draft: Bool?
    let pullRequest: PullRequest?

    /// レスポンスボディを読む。形が崩れていれば nil。
    static func decode(from data: Data) -> IssueSummary? {
        try? APIJSON.decoder().decode(IssueSummary.self, from: data)
    }

    /// 件名の今の状態。知らない値なら nil。
    var subjectState: SubjectState? {
        if let pullRequest {
            if pullRequest.mergedAt != nil { return .merged }
            switch state {
            case "closed": return .closed
            case "open": return draft == true ? .draft : .open
            default: return nil
            }
        }
        switch state {
        case "open": return .open
        // 完了以外の理由（`not_planned`・`duplicate` など、知らない値も）は、完了として出さない
        case "closed": return stateReason == nil || stateReason == "completed" ? .closedCompleted : .closedNotPlanned
        default: return nil
        }
    }
}

/// Timeline の 1 項目のうち、イベントを決めるのに使う値だけ。コメントの本文などは型に載せない。
struct TimelineItem: Decodable, Sendable {
    struct Committer: Decodable, Sendable {
        let date: String?
    }

    let event: String?
    let createdAt: String?
    let submittedAt: String?
    let state: String?
    let actor: IssueSummary.Login?
    let user: IssueSummary.Login?
    let committer: Committer?

    /// Timeline の 1 ページを読む。形の崩れた項目は 1 件ずつ読み飛ばす。ボディ全体が JSON の配列でなければ nil。
    static func decodePage(from data: Data) -> [TimelineItem]? {
        APIJSON.decodeArray(TimelineItem.self, from: data)
    }
}

/// Issue と Timeline から、スレッドの `updated_at` を更新したイベントを決める（github-api「スレッドのイベントの決定」）。
enum ThreadEventResolver {
    /// 作成と同時に起きる出来事を除く幅（作成日時からこの秒数以内は候補にしない）
    static let creationMargin: TimeInterval = 60
    /// 近さの幅: `updated_at` のこの秒数前から
    static let windowBefore: TimeInterval = 180
    /// 近さの幅: `updated_at` のこの秒数後まで
    static let windowAfter: TimeInterval = 60
    /// `closed` をマージとみなす、`closed` の前の `merged` の幅
    static let mergeMargin: TimeInterval = 60

    private struct Candidate {
        let kind: ThreadEvent.Kind
        let date: Date
        let actor: String?
    }

    /// イベント。決められなければ nil。`timeline` は取得したページを古い順につなげたもの。
    static func event(issue: IssueSummary, timeline: [TimelineItem], updatedAt: Date) -> ThreadEvent? {
        guard let createdAt = date(issue.createdAt) else { return nil }
        let candidates = timeline.compactMap(candidate(from:))
        guard let chosen = closest(in: candidates, createdAt: createdAt, updatedAt: updatedAt) else {
            return isNear(createdAt, to: updatedAt) ? ThreadEvent(kind: .opened, actor: issue.user?.login) : nil
        }
        guard chosen.kind == .closed else { return ThreadEvent(kind: chosen.kind, actor: chosen.actor) }
        if let merge = candidates.last(where: { $0.kind == .merged && isJustBefore($0.date, chosen.date) }) {
            return ThreadEvent(kind: .merged, actor: merge.actor)
        }
        // `merged` が取っていない前のページにあっても、Pull request の `merged_at` で分かる（実行者は `closed` のもの）
        if let mergedAt = issue.pullRequest?.mergedAt.flatMap(date), isJustBefore(mergedAt, chosen.date) {
            return ThreadEvent(kind: .merged, actor: chosen.actor)
        }
        return ThreadEvent(kind: .closed, actor: chosen.actor)
    }

    /// `items` に、時刻が近さの幅の始まり（`updated_at` − `windowBefore`）以前の項目があるか。あれば、それより前のページの
    /// 項目は近さの幅に入らない（Timeline は古い順に並ぶ）。コミットの時刻（`committer.date`）は Timeline の並びと
    /// 合わない（古い日付のまま後から push される）ので使わない。
    static func reachesBeforeWindow(_ items: [TimelineItem], updatedAt: Date) -> Bool {
        items.contains { item in
            [item.createdAt, item.submittedAt].compactMap { $0.flatMap(date) }.contains {
                $0 <= updatedAt - windowBefore
            }
        }
    }

    /// `date` が `closedAt` の `mergeMargin` 秒前から `closedAt` までに入るか。
    private static func isJustBefore(_ date: Date, _ closedAt: Date) -> Bool {
        date <= closedAt && date >= closedAt - mergeMargin
    }

    /// 近さの幅に入る候補のうち `updated_at` にいちばん近いもの（同じ近さなら後ろのもの）。無ければ nil。
    private static func closest(in candidates: [Candidate], createdAt: Date, updatedAt: Date) -> Candidate? {
        candidates
            .filter { $0.date > createdAt + creationMargin && isNear($0.date, to: updatedAt) }
            .reduce(nil) { closest, next -> Candidate? in
                guard let closest else { return next }
                return distance(next, updatedAt) <= distance(closest, updatedAt) ? next : closest
            }
    }

    private static func distance(_ candidate: Candidate, _ updatedAt: Date) -> TimeInterval {
        abs(candidate.date.timeIntervalSince(updatedAt))
    }

    private static func isNear(_ date: Date, to updatedAt: Date) -> Bool {
        date >= updatedAt - windowBefore && date <= updatedAt + windowAfter
    }

    /// `created_at` を時刻に、`actor.login` を実行者にするイベント
    private static let actorEvents: [String: ThreadEvent.Kind] = [
        "commented": .commented, "closed": .closed, "reopened": .reopened, "merged": .merged,
        "ready_for_review": .readyForReview, "convert_to_draft": .convertedToDraft,
        "review_requested": .reviewRequested, "assigned": .assigned, "head_ref_force_pushed": .forcePushed,
    ]

    /// `reviewed` の `state` ごとのイベント
    private static let reviewStates: [String: ThreadEvent.Kind] = [
        "approved": .approved, "changes_requested": .changesRequested, "commented": .reviewed,
    ]

    /// 候補にする項目なら、そのイベントと時刻と実行者。候補にしない・時刻を読めない項目は nil。
    private static func candidate(from item: TimelineItem) -> Candidate? {
        switch item.event {
        case "reviewed":
            guard let kind = item.state.flatMap({ reviewStates[$0] }) else { return nil }
            return candidate(kind, at: item.submittedAt, by: item.user?.login)
        case "committed":
            return candidate(.pushedCommits, at: item.committer?.date, by: nil)
        default:
            guard let kind = item.event.flatMap({ actorEvents[$0] }) else { return nil }
            return candidate(kind, at: item.createdAt, by: item.actor?.login)
        }
    }

    private static func candidate(_ kind: ThreadEvent.Kind, at time: String?, by actor: String?) -> Candidate? {
        time.flatMap(date).map { Candidate(kind: kind, date: $0, actor: actor) }
    }

    static func date(_ text: String) -> Date? {
        try? Date(text, strategy: .iso8601)
    }
}
