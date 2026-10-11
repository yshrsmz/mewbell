import SwiftUI

/// 1 つのリポジトリの見出しとスレッド。見出しで折りたたむ。
struct RepositoryGroupView: View {
    let group: RepositoryGroup
    let account: AccountID
    /// このアカウントの折りたたみの状態
    let expansion: AccountExpansion
    let actions: ThreadListActions

    private var isCollapsed: Bool { expansion.isRepositoryCollapsed(group.repository) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                DisclosureButton(
                    isCollapsed: isCollapsed, name: group.repository.description,
                    count: group.threads.count
                ) {
                    expansion.toggleRepository(group.repository)
                } label: {
                    Text(group.repository.description)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
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
}

#Preview("Collapsed") {
    let alice = Account(id: AccountID(host: "github.com", user: "alice"), isActive: true)
    let bob = Account(id: AccountID(host: "github.com", user: "bob"), isActive: false)
    let dave = Account(id: AccountID(host: "acme.ghe.com", user: "dave"), isActive: true)
    // 長いホスト名（見出しが 1 行に収まり、ホスト名が省略されるのを見る）
    let erin = Account(id: AccountID(host: "notifications.ghes.engineering.example.com", user: "erin"), isActive: true)
    let now = Date()
    func thread(_ id: Int, _ repo: String, number: Int?) -> NotificationThread? {
        RepositoryName(fullName: repo).map { repository in
            NotificationThread(
                id: "\(id)", reason: "review_requested", updatedAt: now.addingTimeInterval(-Double(id) * 600),
                title: "Make the menu bar popover remember its scroll position across openings and restarts",
                kind: number == nil ? .release : .pullRequest,
                subjectURL: number.flatMap { URL(string: "https://api.github.com/repos/\(repo)/pulls/\($0)") },
                repository: repository, subjectNumber: number.map(String.init))
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
        erin.id: FeedState(
            phase: .loaded(updatedAt: now), threads: [thread(7, "team/svc", number: 12)].compactMap { $0 }),
    ]
    return NotificationListView(
        statuses: [
            AccountStatus(account: alice, tokenState: .ready),
            AccountStatus(account: bob, tokenState: .ready),
            AccountStatus(account: dave, tokenState: .ready),
            AccountStatus(account: erin, tokenState: .ready),
        ],
        feeds: feeds, repositories: feeds.mapValues { RepositoryGroup.groups(from: $0.threads) },
        participatingOnly: { $0 == erin.id }, expansion: expansion, actions: .none
    )
    .padding()
    .frame(width: 380)
}
