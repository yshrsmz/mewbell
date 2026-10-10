import SwiftUI

/// 1 つのリポジトリの見出しとスレッド。見出しで折りたたむ。
struct RepositoryGroupView: View {
    let group: RepositoryGroup
    let account: AccountID
    let endpoints: APIEndpoints?
    let expansion: ListExpansion
    let actions: ThreadListActions

    private var key: RepositoryKey { RepositoryKey(account: account, repository: group.repository) }
    private var isCollapsed: Bool { expansion.isCollapsed(key) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            DisclosureButton(isCollapsed: isCollapsed, name: group.repository.description) {
                expansion.toggle(key)
            } label: {
                Text(group.repository.description)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if isCollapsed {
                    CollapsedCount(count: group.threads.count)
                }
                Spacer(minLength: 0)
            }
            if !isCollapsed {
                ForEach(group.threads) { thread in
                    ThreadRow(
                        thread: thread,
                        number: endpoints.flatMap { ThreadWebURL.subjectNumber(for: thread, endpoints: $0) },
                        open: { actions.open(thread, account) },
                        markRead: { actions.markRead(thread, account) },
                        markDone: { actions.markDone(thread, account) })
                }
            }
        }
    }
}

/// 見出しの開閉のボタン。先頭に山形を置き、ツールチップとアクセシビリティのラベルを `Expand` / `Collapse` で切り替える。
/// 開閉には短いアニメーションを付けるが、「視差効果を減らす」がオンのときは付けない。
struct DisclosureButton<Label: View>: View {
    let isCollapsed: Bool
    /// ツールチップとラベルに出す名前（ユーザー名、`owner/name`）
    let name: String
    let toggle: () -> Void
    @ViewBuilder let label: Label

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let hint = isCollapsed ? "Expand \(name)" : "Collapse \(name)"
        Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2), toggle)
        } label: {
            HStack(spacing: 6) {
                DisclosureChevron(isCollapsed: isCollapsed)
                label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(hint)
        .accessibilityLabel(hint)
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
