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
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(thread.title)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 4) {
                        Text(NotificationGrouping.reasonText(thread.reason))
                        Text("·")
                        RelativeTimeText(date: thread.updatedAt)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .help("Open in browser and mark as read")
        .overlay(alignment: .trailing) {
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

/// 行に重ねる「既読にする」「Done にする」のボタン。件名の上に重なるので、背景で下の文字を隠す。
private struct ThreadActionButtons: View {
    let markRead: () -> Void
    let markDone: () -> Void

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
        .background(.background, in: RoundedRectangle(cornerRadius: 5))
    }
}

/// アカウントの通知をすべて既読にするボタン。1 回目で確認の表示に変わり、5 秒以内にもう一度押したときだけ実行する。
struct MarkAllReadButton: View {
    let count: Int
    /// 一覧の最新のスレッドの `updated_at`。確認の途中で変わったら確認からやり直す
    let newest: Date?
    let isEnabled: Bool
    /// `participating=true` で取得している（`PUT /notifications` は一覧に出ていない未読も既読にするので、件数を出さない）
    let participatingOnly: Bool
    let action: () -> Void

    @State private var confirming: Bool

    init(
        count: Int, newest: Date?, isEnabled: Bool, participatingOnly: Bool = false, confirming: Bool = false,
        action: @escaping () -> Void
    ) {
        self.count = count
        self.newest = newest
        self.isEnabled = isEnabled
        self.participatingOnly = participatingOnly
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
                Text(participatingOnly ? "Mark all as read?" : "Mark \(count) as read?")
                    .font(.caption.weight(.semibold))
            } else {
                Image(systemName: "checkmark.circle")
            }
        }
        .buttonStyle(.borderless)
        .tint(confirming ? .accentColor : nil)
        .disabled(!isEnabled)
        .help(help)
        .accessibilityLabel(accessibilityLabel)
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

extension MarkAllReadButton {
    private static let includesHidden =
        "Also marks notifications you are not participating in as read, including ones not shown here."

    private var help: String {
        let base = confirming ? "Click again to mark all as read" : "Mark all as read"
        return participatingOnly ? "\(base). \(Self.includesHidden)" : base
    }

    private var accessibilityLabel: String {
        if participatingOnly {
            return confirming
                ? "Confirm marking all as read. \(Self.includesHidden)" : "Mark all as read. \(Self.includesHidden)"
        }
        return confirming ? "Confirm marking \(count) as read" : "Mark all as read"
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
    }
    .padding()
}

#Preview("Thread row hovered") {
    let thread = RepositoryName(owner: "octo", name: "app").map { repository in
        NotificationThread(
            id: "1", reason: "review_requested", updatedAt: Date().addingTimeInterval(-300),
            title: "Make the menu bar popover remember its scroll position across openings and restarts",
            kind: .pullRequest, subjectURL: nil, repository: repository)
    }
    return VStack(alignment: .leading) {
        if let thread {
            ThreadRow(thread: thread, open: {}, markRead: {}, markDone: {})
            ThreadRow(thread: thread, isHovering: true, open: {}, markRead: {}, markDone: {})
        }
    }
    .padding()
    .frame(width: 348)
}
