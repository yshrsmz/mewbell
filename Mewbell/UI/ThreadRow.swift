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
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: ListLayout.chevronWidth)
                VStack(alignment: .leading, spacing: 1) {
                    Text(thread.title)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 4) {
                        if let number = thread.subjectNumber {
                            Text("#\(number)")
                                .monospacedDigit()
                            Text("·")
                        }
                        Text(ThreadReason.text(thread.reason))
                        Text("·")
                        RelativeTimeText(date: thread.updatedAt)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .help("Open in browser and mark as read")
        // ホバーのボタンの下に件名が透けないよう、ボタンの範囲と手前を消す（折り返しは変えないので行の高さは動かない）
        .mask {
            Rectangle()
                .overlay(alignment: .topTrailing) {
                    if isHovering {
                        ThreadActionButtons.titleFade
                    }
                }
                .compositingGroup()
        }
        // 上端に揃えて件名の 1 行目の高さに置く（件名が 2 行の行でも位置が変わらず、Done で繰り上がった行でもカーソルの下に来るように）
        .overlay(alignment: .topTrailing) {
            if isHovering {
                ThreadActionButtons(markRead: markRead, markDone: markDone)
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

    private var symbol: String {
        switch thread.kind {
        case .pullRequest: "arrow.triangle.pull"
        case .issue: "smallcircle.filled.circle"
        case .commit: "point.3.connected.trianglepath.dotted"
        case .release: "tag"
        case .discussion: "bubble.left.and.bubble.right"
        case .checkSuite, .other: "bell"
        }
    }
}

/// 行に重ねる「既読にする」「Done にする」のボタン。件名の上に重なるので、行は `titleFade` でボタンの下の文字を消す。
/// （背景で隠すと、ポップオーバーの半透明の背景では下の文字が透けて見える）
private struct ThreadActionButtons: View {
    let markRead: () -> Void
    let markDone: () -> Void

    /// ボタンの大きさ（22 × 2、間隔 2、左右の余白 2 × 2）
    private static let size = CGSize(width: 22 * 2 + 2 + 2 * 2, height: 22)
    /// ボタンの手前で件名を薄くしていく幅
    private static let fadeWidth: CGFloat = 16

    /// 行のマスクから抜く形。ボタンの範囲を消し、その手前をだんだん薄くする
    static var titleFade: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: fadeWidth)
            Color.black
                .frame(width: size.width)
        }
        .frame(height: size.height)
        .blendMode(.destinationOut)
    }

    var body: some View {
        HStack(spacing: 2) {
            Button(action: markRead) {
                Image(systemName: "envelope.open")
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .help("Mark as read")
            .accessibilityLabel("Mark as read")
            Button(action: markDone) {
                Image(systemName: "checkmark")
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .help("Mark as done")
            .accessibilityLabel("Mark as done")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 2)
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
        Button {
            if confirming {
                confirming = false
                action()
            } else {
                confirming = true
            }
        } label: {
            if confirming {
                Text(labels.confirmation)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize()
            } else {
                Image(systemName: "checkmark.circle")
            }
        }
        .buttonStyle(.borderless)
        .tint(confirming ? .accentColor : nil)
        .disabled(!isEnabled)
        .help(labels.help(confirming: confirming))
        .accessibilityLabel(labels.accessibilityLabel(confirming: confirming))
        // 確認の表示は 5 秒で戻す（`confirming` が変わると前の待ちは取り消される）
        .task(id: confirming) {
            guard confirming else { return }
            guard (try? await Task.sleep(for: .seconds(5))) != nil else { return }
            confirming = false
        }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled {
                confirming = false
            }
        }
        // 確認の途中で一覧が変わったら（件数か最新のスレッド）、見ていないスレッドまで既読にしないように確認からやり直す
        .onChange(of: count) { confirming = false }
        .onChange(of: newest) { confirming = false }
        .onDisappear { confirming = false }
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

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            // 文字列にしてから渡す（時刻が進むと文字列が変わり、描き直される）
            Text(date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
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

#Preview("Thread row hovered") {
    func thread(number: String?) -> NotificationThread? {
        RepositoryName(owner: "octo", name: "app").map { repository in
            NotificationThread(
                id: "1", reason: "review_requested", updatedAt: Date().addingTimeInterval(-300),
                title: "Make the menu bar popover remember its scroll position across openings and restarts",
                kind: .pullRequest, subjectURL: nil, repository: repository, subjectNumber: number)
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
