import SwiftUI

/// スレッドの行。クリックでブラウザで開いて既読にする。マウスを載せると、開かずに既読・Done にするボタンが出る。
struct ThreadRow: View {
    let thread: NotificationThread
    let open: () -> Void
    let markRead: () -> Void
    let markDone: () -> Void

    @State private var isHovering: Bool

    /// `isHovering` はプレビューでボタンを出しておくため。
    init(
        thread: NotificationThread, isHovering: Bool = false, open: @escaping () -> Void,
        markRead: @escaping () -> Void, markDone: @escaping () -> Void
    ) {
        self.thread = thread
        self.open = open
        self.markRead = markRead
        self.markDone = markDone
        _isHovering = State(initialValue: isHovering)
    }

    var body: some View {
        // 操作のボタンは行のボタンの中に入れず、上に重ねる（行のクリックと奪い合わないように）
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: ListLayout.spacing) {
                Image(systemName: icon.symbol)
                    .foregroundStyle(icon.color.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
                    .frame(width: ListLayout.iconColumnWidth)
                    .accessibilityLabel(icon.label)
                VStack(alignment: .leading, spacing: 1) {
                    Text(thread.title)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    // 1 つの文にして、狭いときは部分ごとではなく文として折り返す
                    RelativeTimeText(date: thread.updatedAt, prefix: details)
                        .monospacedDigit()
                        .multilineTextAlignment(.leading)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
            // ホバーのボタンの下に件名が透けないよう、ボタンの範囲と手前を消す（折り返しは変えないので行の高さは動かない）。
            // ラベルにだけ掛け、スタイルの塗りはボタンの下にも残す
            .mask {
                Rectangle()
                    .overlay(alignment: .topTrailing) {
                        if isHovering {
                            HoverActionButtons.titleFade
                        }
                    }
                    .compositingGroup()
            }
        }
        // 操作のボタンに載せている間も行を塗るよう、行全体のホバーの状態で塗る
        .buttonStyle(HoverHighlightButtonStyle(isHovering: isHovering))
        .help("Open in browser and mark as read")
        // 上端に揃えて件名の 1 行目の高さに置く（件名が 2 行の行でも位置が変わらず、Done で繰り上がった行でもカーソルの下に来るように）
        .overlay(alignment: .topTrailing) {
            if isHovering {
                HoverActionButtons(readLabel: "Mark as read", markRead: markRead) {
                    Button(action: markDone) {
                        HoverActionButtons.icon("checkmark")
                    }
                    .help("Mark as done")
                    .accessibilityLabel("Mark as done")
                }
            }
        }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Open in Browser", action: open)
            Button("Mark as Read", action: markRead)
            Button("Mark as Done", action: markDone)
        }
        // ホバーのボタンを使えない VoiceOver でも操作できるように
        .accessibilityAction(named: "Mark as Read", markRead)
        .accessibilityAction(named: "Mark as Done", markDone)
    }

    /// 件名の下の行の、更新日時の前の部分（番号、イベント、理由）。
    private var details: [String] {
        [
            number, thread.details?.event.map(ThreadEventText.text), ThreadReason.text(thread.reason),
        ].compactMap { $0 }
    }

    /// Issue・Pull request の番号（`#<番号>`）。番号を持たなければ nil。
    private var number: String? {
        guard case .number(let number) = thread.detailsSubject else { return nil }
        return "#\(number)"
    }

    private var icon: ThreadIcon {
        ThreadIcon(kind: thread.kind, state: thread.details?.state)
    }
}

/// アカウントの通知をすべて既読にするボタン。1 回目で確認の表示に変わり、5 秒以内にもう一度押したときだけ実行する。
struct MarkAllReadButton: View {
    let count: Int
    /// 一覧の最新のスレッドの `updated_at`。確認の途中で変わったら確認からやり直す
    let newest: Date?
    let isEnabled: Bool
    /// ボタンの文（一覧に出ていない未読も既読にすることになるときは、件数を出さない）
    let labels: MarkAllReadLabels
    let action: () -> Void

    @State private var confirming: Bool

    /// `participatingOnly` は `participating=true` で取得している、`isTruncated` は一覧を 10 ページで打ち切った
    /// （どちらも `PUT /notifications` が一覧に出ていない未読まで既読にする）。
    init(
        count: Int, newest: Date?, isEnabled: Bool, participatingOnly: Bool = false, isTruncated: Bool = false,
        confirming: Bool = false, action: @escaping () -> Void
    ) {
        self.count = count
        self.newest = newest
        self.isEnabled = isEnabled
        labels = MarkAllReadLabels(count: count, participatingOnly: participatingOnly, isTruncated: isTruncated)
        self.action = action
        _confirming = State(initialValue: confirming)
    }

    var body: some View {
        ConfirmingButton(
            confirming: $confirming, icon: Image(systemName: "checkmark.circle"), confirmation: labels.confirmation,
            help: labels.help(confirming: confirming),
            accessibilityLabel: labels.accessibilityLabel(confirming: confirming), isEnabled: isEnabled,
            count: count, newest: newest, outset: 3, action: action)
    }
}

/// すべて既読のボタンの文。一覧に出ていない未読も既読になるとき（参加しているスレッドだけ、10 ページで打ち切った）は
/// 件数を出さず、そのことをツールチップと読み上げで伝える。
struct MarkAllReadLabels: Equatable {
    let count: Int
    let participatingOnly: Bool
    let isTruncated: Bool

    private static let notParticipating =
        "Also marks threads you are not participating in as read, up to the newest one shown here."
    private static let olderThanShown =
        "Also marks older unread threads that are not shown here as read (only the newest \(GitHubAPIClient.threadLimit) are fetched)."

    /// 一覧に出ていない未読も既読にすることになるか
    var includesUnlisted: Bool { participatingOnly || isTruncated }

    var confirmation: String {
        includesUnlisted ? "Mark all as read?" : "Mark \(count) as read?"
    }

    func help(confirming: Bool) -> String {
        withNotes(confirming ? "Click again to mark all as read" : "Mark all as read")
    }

    func accessibilityLabel(confirming: Bool) -> String {
        guard confirming else { return withNotes("Mark all as read") }
        return withNotes(includesUnlisted ? "Confirm marking all as read" : "Confirm marking \(count) as read")
    }

    private func withNotes(_ base: String) -> String {
        let notes = [participatingOnly ? Self.notParticipating : nil, isTruncated ? Self.olderThanShown : nil]
            .compactMap { $0 }
        return notes.isEmpty ? base : "\(base). \(notes.joined(separator: " "))"
    }
}

/// 「5 min. ago」のような相対時刻。ポップオーバーを開いている間も 30 秒ごとに更新する。
struct RelativeTimeText: View {
    let date: Date
    /// 時刻の前に ` · ` でつないで出す文
    var prefix: [String] = []

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            // 文字列にしてから渡す（時刻が進むと文字列が変わり、描き直される）。折り返すのは ` · ` の後だけにする
            Text(
                (prefix + [date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))])
                    .map { $0.replacing(" ", with: "\u{00A0}") }
                    .joined(separator: " · "))
        }
    }
}

#Preview("Mark all as read") {
    VStack(alignment: .trailing, spacing: 12) {
        MarkAllReadButton(count: 3, newest: .now, isEnabled: true) {}
        MarkAllReadButton(count: 3, newest: .now, isEnabled: true, confirming: true) {}
        MarkAllReadButton(count: 0, newest: nil, isEnabled: false) {}
        MarkAllReadButton(count: 2, newest: .now, isEnabled: true, participatingOnly: true, confirming: true) {}
        MarkAllReadButton(count: 500, newest: .now, isEnabled: true, isTruncated: true) {}
        MarkAllReadButton(count: 500, newest: .now, isEnabled: true, isTruncated: true, confirming: true) {}
    }
    .padding()
}

#Preview("Thread row states") {
    func thread(_ id: String, _ kind: SubjectKind, _ state: SubjectState?, _ event: ThreadEvent?) -> NotificationThread?
    {
        RepositoryName(owner: "octo", name: "app").map { repository in
            NotificationThread(
                id: id, reason: "subscribed", updatedAt: Date().addingTimeInterval(-180), title: "Fix the login flow",
                kind: kind, subjectURL: nil, repository: repository, detailsSubject: .number("42"),
                details: ThreadDetails(state: state, event: event))
        }
    }
    let threads = [
        thread("1", .pullRequest, .open, ThreadEvent(kind: .pushedCommits, actor: nil)),
        thread("2", .pullRequest, .draft, ThreadEvent(kind: .convertedToDraft, actor: "alice")),
        thread("3", .pullRequest, .merged, ThreadEvent(kind: .merged, actor: "dependabot[bot]")),
        thread("4", .pullRequest, .closed, ThreadEvent(kind: .closed, actor: "alice")),
        thread("5", .issue, .open, ThreadEvent(kind: .commented, actor: "bob")),
        thread("6", .issue, .closedCompleted, ThreadEvent(kind: .closed, actor: "alice")),
        thread("7", .issue, .closedNotPlanned, nil),
        thread("8", .issue, nil, nil),
    ].compactMap { $0 }
    return VStack(alignment: .leading) {
        ForEach(threads) { ThreadRow(thread: $0, open: {}, markRead: {}, markDone: {}) }
    }
    .padding()
    .frame(width: 348)
}

#Preview("Thread row hovered") {
    func thread(number: String?) -> NotificationThread? {
        RepositoryName(owner: "octo", name: "app").map { repository in
            NotificationThread(
                id: "1", reason: "review_requested", updatedAt: Date().addingTimeInterval(-300),
                title: "Make the menu bar popover remember its scroll position across openings and restarts",
                kind: .pullRequest, subjectURL: nil, repository: repository,
                detailsSubject: number.map(DetailsSubject.number))
        }
    }
    return VStack(alignment: .leading) {
        if let plain = thread(number: nil), let numbered = thread(number: "1234") {
            ThreadRow(thread: plain, open: {}, markRead: {}, markDone: {})
            ThreadRow(thread: numbered, open: {}, markRead: {}, markDone: {})
            ThreadRow(thread: numbered, isHovering: true, open: {}, markRead: {}, markDone: {})
        }
    }
    .padding()
    .frame(width: 348)
}
