import Foundation

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
