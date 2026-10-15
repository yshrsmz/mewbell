import SwiftUI

/// 1 つのリポジトリの見出しとスレッド。見出しで折りたたむ。見出しにマウスを載せると、グループのスレッドを
/// まとめて既読・Done にするボタンが出る。Done は 2 回押して実行する（コンテキストメニューと VoiceOver からは確認の表示にするだけ）。
struct RepositoryGroupView: View {
    let group: RepositoryGroup
    let account: AccountID
    /// このアカウントの折りたたみの状態
    let expansion: AccountExpansion
    let actions: ThreadListActions

    @State private var isHovering: Bool
    @State private var confirmingDone: Bool
    /// 重ねたボタンの幅（見出しの中身をその手前で省略する）
    @State private var actionsWidth: CGFloat = 0

    /// `isHovering` と `confirmingDone` はプレビューでボタンと確認の表示を出しておくため。
    init(
        group: RepositoryGroup, account: AccountID, expansion: AccountExpansion, actions: ThreadListActions,
        isHovering: Bool = false, confirmingDone: Bool = false
    ) {
        self.group = group
        self.account = account
        self.expansion = expansion
        self.actions = actions
        _isHovering = State(initialValue: isHovering)
        _confirmingDone = State(initialValue: confirmingDone)
    }

    private var isCollapsed: Bool { expansion.isRepositoryCollapsed(group.repository) }
    private var labels: RepositoryActionLabels {
        RepositoryActionLabels(repository: group.repository.description, count: group.threads.count)
    }
    /// 確認の表示はマウスを外しても出し続ける
    private var showsActions: Bool { isHovering || confirmingDone }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // 操作のボタンは開閉のボタンの中に入れず、上に重ねる（見出しのクリックと奪い合わないように）
            DisclosureButton(
                isCollapsed: isCollapsed, name: group.repository.description,
                count: group.threads.count, isHovering: isHovering,
                trailingInset: showsActions ? actionsWidth : 0
            ) {
                expansion.toggleRepository(group.repository)
            } label: {
                OneLineText(text: group.repository.description, truncation: .middle)
                    .font(.subheadline.weight(.semibold))
            }
            // ホバーのボタンを使えない VoiceOver でも操作できるように（Done は確認の表示にするだけ）
            .accessibilityAction(named: labels.read, markRead)
            .accessibilityAction(named: labels.done) { confirmingDone = true }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .trailing) {
                if showsActions {
                    actionButtons
                }
            }
            .onHover { isHovering = $0 }
            .contextMenu {
                Button("Mark All as Read", action: markRead)
                Button("Mark All as Done") { confirmingDone = true }
            }
            if !isCollapsed {
                ForEach(group.threads) { thread in
                    ThreadRow(
                        thread: thread,
                        open: { actions.open(thread, account) },
                        markRead: { actions.markRead(thread, account) },
                        markDone: { actions.markDone(thread, account) })
                }
            }
        }
    }

    private var actionButtons: some View {
        HoverActionButtons(readLabel: labels.read, markRead: markRead) {
            ConfirmingButton(
                confirming: $confirmingDone, icon: HoverActionButtons.icon("checkmark"),
                confirmation: labels.confirmation, help: labels.doneHelp(confirming: confirmingDone),
                accessibilityLabel: labels.doneAccessibilityLabel(confirming: confirmingDone),
                count: group.threads.count, newest: group.threads.first?.updatedAt
            ) {
                actions.markGroupDone(group, account)
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            actionsWidth = $0
        }
    }

    private func markRead() {
        actions.markGroupRead(group, account)
    }
}

/// リポジトリの見出しの操作の文。どのリポジトリへの操作かが分かるように、リポジトリ名を入れる。
struct RepositoryActionLabels: Equatable {
    /// `owner/name`
    let repository: String
    /// グループのスレッドの件数
    let count: Int

    var read: String { "Mark all in \(repository) as read" }
    var done: String { "Mark all in \(repository) as done" }
    var confirmation: String { "Mark \(count) as done?" }

    func doneHelp(confirming: Bool) -> String {
        confirming ? "Click again to mark \(count) in \(repository) as done" : done
    }

    func doneAccessibilityLabel(confirming: Bool) -> String {
        confirming ? "Confirm marking \(count) in \(repository) as done" : done
    }
}

#Preview("Collapsed") {
    let alice = Account(id: AccountID(host: "github.com", user: "alice"), isActive: true)
    let bob = Account(id: AccountID(host: "github.com", user: "bob"), isActive: false)
    let dave = Account(id: AccountID(host: "acme.ghe.com", user: "dave"), isActive: true)
    // 長いホスト名（見出しが 1 行に収まり、ホスト名が省略されるのを見る）
    let grace = Account(
        id: AccountID(host: "notifications.ghes.engineering.example.com", user: "grace"), isActive: true)
    let now = Date()
    func thread(_ id: Int, _ repo: String, number: Int?) -> NotificationThread? {
        RepositoryName(fullName: repo).map { repository in
            NotificationThread(
                id: "\(id)", reason: "review_requested", updatedAt: now.addingTimeInterval(-Double(id) * 600),
                title: "Make the menu bar popover remember its scroll position across openings and restarts",
                kind: number == nil ? .release : .pullRequest,
                subjectURL: number.flatMap { URL(string: "https://api.github.com/repos/\(repo)/pulls/\($0)") },
                repository: repository, detailsSubject: number.map { .number(String($0)) })
        }
    }
    let expansion = ListExpansion()
    expansion.state(for: alice.id).toggle()
    expansion.state(for: dave.id).toggle()
    if let app = RepositoryName(fullName: "octo/app") {
        expansion.state(for: bob.id).toggleRepository(app)
    }
    let feeds: [AccountID: FeedState] = [
        alice.id: FeedState(
            phase: .loaded(updatedAt: now), threads: [thread(1, "octo/app", number: 1)].compactMap { $0 }),
        bob.id: FeedState(
            phase: .loaded(updatedAt: now),
            threads: [
                thread(2, "octo/app", number: 42), thread(3, "octo/app", number: 43),
                thread(4, "octo/lib", number: 1234), thread(5, "octo/lib", number: nil),
            ].compactMap { $0 }),
        dave.id: FeedState(
            phase: .retrying(nextAttempt: now.addingTimeInterval(240), rateLimited: true),
            threads: [thread(6, "acme/web", number: 7)].compactMap { $0 }),
        grace.id: FeedState(
            phase: .loaded(updatedAt: now), threads: [thread(7, "team/svc", number: 12)].compactMap { $0 }),
    ]
    return NotificationListView(
        statuses: [
            AccountStatus(account: alice, tokenState: .ready),
            AccountStatus(account: bob, tokenState: .ready),
            AccountStatus(account: dave, tokenState: .ready),
            AccountStatus(account: grace, tokenState: .ready),
        ],
        feeds: feeds, repositories: feeds.mapValues { RepositoryGroup.groups(from: $0.threads) },
        participatingOnly: { $0 == grace.id }, expansion: expansion, actions: .none
    )
    .padding()
    .frame(width: 380)
}

#Preview("Repository actions") {
    let alice = AccountID(host: "github.com", user: "alice")
    let now = Date()
    func group(_ repo: String, count: Int) -> RepositoryGroup? {
        RepositoryName(fullName: repo).map { repository in
            RepositoryGroup(
                repository: repository,
                threads: (1...count).map { id in
                    NotificationThread(
                        id: "\(id)", reason: "subscribed", updatedAt: now.addingTimeInterval(-Double(id) * 600),
                        title: "Bump the dependencies of the release workflow", kind: .pullRequest, subjectURL: nil,
                        repository: repository, detailsSubject: nil)
                })
        }
    }
    let expansion = ListExpansion()
    let long = group("octo/a-repository-with-a-very-long-name-that-fills-the-heading", count: 2)
    if let long {
        expansion.state(for: alice).toggleRepository(long.repository)
    }
    return VStack(alignment: .leading, spacing: 12) {
        if let app = group("octo/app", count: 2), let lib = group("octo/lib", count: 3), let long {
            // ホバー中、Done の確認中、長い名前を畳んだ見出しのホバー中
            RepositoryGroupView(
                group: app, account: alice, expansion: expansion.state(for: alice), actions: .none, isHovering: true)
            RepositoryGroupView(
                group: lib, account: alice, expansion: expansion.state(for: alice), actions: .none,
                confirmingDone: true)
            RepositoryGroupView(
                group: long, account: alice, expansion: expansion.state(for: alice), actions: .none, isHovering: true)
        }
    }
    .padding()
    .frame(width: 348)
}
