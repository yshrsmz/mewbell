import SwiftUI

/// スレッドの行のアイコン。種類と、分かれば件名の状態を、記号の形と色の両方で表す。
struct ThreadIcon: Equatable {
    let symbol: String
    /// nil なら補足の色（`.secondary`）
    let color: Color?
    /// VoiceOver で読む名前（「Pull request, merged」など）
    let label: String

    init(kind: SubjectKind, state: SubjectState?) {
        let kindName = Self.kindName(kind)
        if let state, let icon = Self.stateIcon(kind: kind, state: state) {
            (symbol, color, label) = (icon.symbol, icon.color, "\(kindName), \(icon.stateName)")
        } else {
            (symbol, color, label) = (Self.kindSymbol(kind), nil, kindName)
        }
    }

    /// 状態ごとの記号・色・状態の名前
    private struct StateIcon {
        let symbol: String
        let color: Color?
        let stateName: String
    }

    /// 状態ごとのアイコン。種類に合わない状態なら nil（種類のアイコンを出す）。
    private static func stateIcon(kind: SubjectKind, state: SubjectState) -> StateIcon? {
        switch (kind, state) {
        case (.pullRequest, .open): StateIcon(symbol: "arrow.triangle.pull", color: .green, stateName: "open")
        case (.pullRequest, .draft): StateIcon(symbol: "circle.dashed", color: nil, stateName: "draft")
        case (.pullRequest, .merged): StateIcon(symbol: "arrow.triangle.merge", color: .purple, stateName: "merged")
        case (.pullRequest, .closed): StateIcon(symbol: "xmark.circle", color: .red, stateName: "closed")
        case (.issue, .open): StateIcon(symbol: "smallcircle.filled.circle", color: .green, stateName: "open")
        case (.issue, .closedCompleted):
            StateIcon(symbol: "checkmark.circle", color: .purple, stateName: "closed as completed")
        case (.issue, .closedNotPlanned):
            StateIcon(symbol: "slash.circle", color: nil, stateName: "closed as not planned")
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
        case .checkSuite, .workflowRun, .other: "bell"
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
        case .workflowRun: "Workflow run"
        case .other: "Notification"
        }
    }
}
