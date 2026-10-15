import Foundation

/// スレッドの `updated_at` を更新した出来事（Issue の Timeline から決める）。
struct ThreadEvent: Hashable, Sendable {
    enum Kind: Hashable, Sendable, CaseIterable {
        case opened
        case commented
        case approved
        case changesRequested
        case reviewed
        case closed
        case reopened
        case merged
        case readyForReview
        case convertedToDraft
        case reviewRequested
        case assigned
        case pushedCommits
        case forcePushed
    }

    let kind: Kind
    /// 検証済みのログイン名（`GhIdentifier.isValidActor`）。無い・検証を通らないときは nil
    let actor: String?

    init(kind: Kind, actor: String?) {
        self.kind = kind
        self.actor = actor.flatMap { GhIdentifier.isValidActor($0) ? $0 : nil }
    }
}

/// Issue・Pull request の件名の今の状態。
enum SubjectState: Hashable, Sendable {
    case open
    /// 下書きの Pull request
    case draft
    case merged
    /// 閉じた Pull request（マージしていない）
    case closed
    /// 完了として閉じた Issue
    case closedCompleted
    /// 対応しないで閉じた Issue
    case closedNotPlanned
}

/// スレッドの件名の状態とイベント（Issue・Pull request）か、開くページを決める取得した値（Release・WorkflowRun・CheckSuite）。
/// 取得できたスレッドにだけ付く。
struct ThreadDetails: Hashable, Sendable {
    /// 件名の種類ごとに取った、開くページを決める値。検証済みの文字列で持ち、`ThreadWebURL` が URL を組み立てるときに
    /// もう一度検証する。
    enum Resource: Hashable, Sendable {
        /// Release のリリースのタグ（`ThreadWebURL.releaseTagComponents` の検証を通ったもの）
        case release(tag: String)
        /// WorkflowRun と CheckSuite の run の ID（1〜20 桁の数字）
        case workflowRun(id: String)
    }

    /// 分からなければ nil（Release・WorkflowRun・CheckSuite では nil）
    let state: SubjectState?
    /// 決められなければ nil（Release・WorkflowRun・CheckSuite では nil）
    let event: ThreadEvent?
    /// Issue・Pull request と、決まらなかったときは nil
    let resource: Resource?

    init(state: SubjectState?, event: ThreadEvent?, resource: Resource? = nil) {
        self.state = state
        self.event = event
        self.resource = resource
    }
}
