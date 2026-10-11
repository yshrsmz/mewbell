import SwiftUI

/// イベントの表示（一覧の行と macOS の通知で使う）。決まったイベント名と、検証済みのログイン名だけを出す。
enum ThreadEventText {
    /// `Closed by alice`、`Pushed commits` など。
    static func text(_ event: ThreadEvent) -> String {
        event.actor.map { "\(name(event.kind)) by \($0)" } ?? name(event.kind)
    }

    static func name(_ kind: ThreadEvent.Kind) -> String {
        names[kind] ?? ""
    }

    private static let names: [ThreadEvent.Kind: String] = [
        .opened: "Opened", .commented: "Commented", .approved: "Approved", .changesRequested: "Requested changes",
        .reviewed: "Reviewed", .closed: "Closed", .reopened: "Reopened", .merged: "Merged",
        .readyForReview: "Marked ready for review", .convertedToDraft: "Converted to draft",
        .reviewRequested: "Requested review", .assigned: "Assigned", .pushedCommits: "Pushed commits",
        .forcePushed: "Force-pushed",
    ]
}

/// スレッドの行のアイコン。種類と、分かれば件名の状態を、記号の形と色の両方で表す。
struct ThreadIcon: Equatable {
    let symbol: String
    /// nil なら補足の色（`.secondary`）
    let color: Color?
    /// VoiceOver で読む名前（「Pull request, merged」など）
    let label: String

    init(kind: SubjectKind, state: SubjectState?) {
        let kindName = Self.kindName(kind)
        guard let state, let icon = Self.stateIcon(kind: kind, state: state) else {
            self.init(symbol: Self.kindSymbol(kind), color: nil, label: kindName)
            return
        }
        self.init(symbol: icon.symbol, color: icon.color, label: "\(kindName), \(icon.label)")
    }

    private init(symbol: String, color: Color?, label: String) {
        self.symbol = symbol
        self.color = color
        self.label = label
    }

    /// 状態ごとの記号・色・状態の名前。種類に合わない状態なら nil（種類のアイコンを出す）。
    private static func stateIcon(kind: SubjectKind, state: SubjectState) -> ThreadIcon? {
        switch (kind, state) {
        case (.pullRequest, .open): ThreadIcon(symbol: "arrow.triangle.pull", color: .green, label: "open")
        case (.pullRequest, .draft): ThreadIcon(symbol: "circle.dashed", color: nil, label: "draft")
        case (.pullRequest, .merged): ThreadIcon(symbol: "arrow.triangle.merge", color: .purple, label: "merged")
        case (.pullRequest, .closed): ThreadIcon(symbol: "xmark.circle", color: .red, label: "closed")
        case (.issue, .open): ThreadIcon(symbol: "smallcircle.filled.circle", color: .green, label: "open")
        case (.issue, .closedCompleted):
            ThreadIcon(symbol: "checkmark.circle", color: .purple, label: "closed as completed")
        case (.issue, .closedNotPlanned):
            ThreadIcon(symbol: "slash.circle", color: nil, label: "closed as not planned")
        default: nil
        }
    }

    private static func kindSymbol(_ kind: SubjectKind) -> String {
        switch kind {
        case .pullRequest: "arrow.triangle.pull"
        case .issue: "smallcircle.filled.circle"
        case .commit: "point.3.connected.trianglepath.dotted"
        case .release: "tag"
        case .discussion: "bubble.left.and.bubble.right"
        case .checkSuite, .other: "bell"
        }
    }

    private static func kindName(_ kind: SubjectKind) -> String {
        switch kind {
        case .pullRequest: "Pull request"
        case .issue: "Issue"
        case .commit: "Commit"
        case .release: "Release"
        case .discussion: "Discussion"
        case .checkSuite: "Check suite"
        case .other: "Notification"
        }
    }
}
