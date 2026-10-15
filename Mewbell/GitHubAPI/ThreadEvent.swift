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

/// スレッドの件名の状態とイベント（Release ではリリースのタグ）。取得できたスレッドにだけ付く。
struct ThreadDetails: Hashable, Sendable {
    /// 分からなければ nil
    let state: SubjectState?
    /// 決められなければ nil
    let event: ThreadEvent?
    /// Release のリリースのタグ（`ThreadWebURL.releaseTagComponents` の検証を通ったもの）。ほかの種類では nil
    let releaseTag: String?

    init(state: SubjectState?, event: ThreadEvent?, releaseTag: String? = nil) {
        self.state = state
        self.event = event
        self.releaseTag = releaseTag
    }
}
