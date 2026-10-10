import SwiftUI

/// 1 つのリポジトリの見出しとスレッド。見出しで折りたたむ。
struct RepositoryGroupView: View {
    let group: RepositoryGroup
    let key: RepositoryKey
    let endpoints: APIEndpoints?
    let expansion: ListExpansion
    let actions: ThreadListActions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isCollapsed: Bool { expansion.isCollapsed(key) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { expansion.toggle(key) }
            } label: {
                HStack(spacing: 6) {
                    DisclosureChevron(isCollapsed: isCollapsed)
                    Text(group.repository.description)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if isCollapsed {
                        CollapsedCount(count: group.threads.count)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isCollapsed ? "Expand \(group.repository.description)" : "Collapse \(group.repository.description)")
            .accessibilityLabel(
                isCollapsed ? "Expand \(group.repository.description)" : "Collapse \(group.repository.description)")
            if !isCollapsed {
                ForEach(group.threads) { thread in
                    ThreadRow(
                        thread: thread,
                        number: endpoints.flatMap { ThreadWebURL.subjectNumber(for: thread, endpoints: $0) },
                        open: { actions.open(thread, key.account) },
                        markRead: { actions.markRead(thread, key.account) },
                        markDone: { actions.markDone(thread, key.account) })
                }
            }
        }
    }
}

/// 開閉を示す山形。開いているときは下を向く。幅はスレッドの行の種類のアイコンと揃える。
struct DisclosureChevron: View {
    let isCollapsed: Bool

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(isCollapsed ? 0 : 90))
            .frame(width: 16)
            .accessibilityHidden(true)
    }
}

/// 折りたたんだ見出しに出す件数。
struct CollapsedCount: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.secondary.opacity(0.15), in: Capsule())
    }
}

#Preview("Collapsed") {
    let alice = Account(id: AccountID(host: "github.com", user: "alice"), isActive: true)
    let bob = Account(id: AccountID(host: "github.com", user: "bob"), isActive: false)
    let dave = Account(id: AccountID(host: "acme.ghe.com", user: "dave"), isActive: true)
    let now = Date()
    func thread(_ id: Int, _ repo: String, number: Int?) -> NotificationThread? {
        RepositoryName(fullName: repo).map { repository in
            NotificationThread(
                id: "\(id)", reason: "review_requested", updatedAt: now.addingTimeInterval(-Double(id) * 600),
                title: "Make the menu bar popover remember its scroll position across openings and restarts",
                kind: number == nil ? .release : .pullRequest,
                subjectURL: number.flatMap { URL(string: "https://api.github.com/repos/\(repo)/pulls/\($0)") },
                repository: repository)
        }
    }
    let expansion = ListExpansion()
    expansion.toggle(alice.id)
    expansion.toggle(dave.id)
    if let app = RepositoryName(fullName: "octo/app") {
        expansion.toggle(RepositoryKey(account: bob.id, repository: app))
    }
    return NotificationListView(
        statuses: [
            AccountStatus(account: alice, tokenState: .ready),
            AccountStatus(account: bob, tokenState: .ready),
            AccountStatus(account: dave, tokenState: .ready),
        ],
        feeds: [
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
        ],
        expansion: expansion, actions: .none
    )
    .padding()
    .frame(width: 380)
}
