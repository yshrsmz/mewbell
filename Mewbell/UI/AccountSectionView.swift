import AppKit
import SwiftUI

/// 一覧での操作。`NotificationStore` に渡す。
struct ThreadListActions {
    /// スレッドがクリックされたとき（ブラウザで開いて既読にする）
    var open: (NotificationThread, AccountID) -> Void
    /// 開かずに既読にする
    var markRead: (NotificationThread, AccountID) -> Void
    var markDone: (NotificationThread, AccountID) -> Void
    var markAllRead: (AccountID) -> Void

    /// 何もしない（プレビュー用）。
    static var none: ThreadListActions {
        ThreadListActions(open: { _, _ in }, markRead: { _, _ in }, markDone: { _, _ in }, markAllRead: { _ in })
    }
}

/// アカウントの区画をアカウントの並び順に並べる。トークンや API の URL は表示しない。
/// 無効のアカウントの区画は出さない。
struct NotificationListView: View {
    let statuses: [AccountStatus]
    let feeds: [AccountID: FeedState]
    /// 「参加しているスレッドだけにする」の設定
    var participatingOnly: (AccountID) -> Bool = { _ in false }
    /// 折りたたみの状態（アプリが 1 つだけ持つ）
    let expansion: ListExpansion
    let actions: ThreadListActions

    var body: some View {
        let shown = statuses.filter { $0.tokenState != .disabled }
        if shown.isEmpty && !statuses.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("All accounts are disabled", systemImage: "pause.circle")
                    .font(.headline)
                Text("Enable an account in Settings to get its notifications.")
                OpenSettingsButton(style: .text)
            }
            .font(.callout)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(shown) { status in
                        AccountSectionView(
                            status: status, feed: feeds[status.id], participatingOnly: participatingOnly(status.id),
                            expansion: expansion, actions: actions)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 480)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 1 アカウントの見出し、取得の状態、リポジトリごとのスレッド。
struct AccountSectionView: View {
    let status: AccountStatus
    let feed: FeedState?
    var participatingOnly = false
    let expansion: ListExpansion
    let actions: ThreadListActions

    private var account: Account { status.account }
    private var isCollapsed: Bool { expansion.isCollapsed(account.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            switch status.tokenState {
            case .fetching where feed == nil:
                Text("Checking gh…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 22)
            case .unavailable:
                Text("Could not get a token from gh. Log in again with:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                CommandRow(command: "gh auth login --hostname \(account.host)")
            case .disabled:
                // 無効のアカウントの区画は `NotificationListView` が出さない
                EmptyView()
            case .fetching, .ready:
                // 401 の後などにトークンを取り直している間も、それまでの状態を出し続ける
                if let feed {
                    FeedStatusView(account: account, phase: feed.phase, isTruncated: feed.isTruncated)
                    if let failure = feed.actionFailure {
                        ActionFailureView(failure: failure, host: account.host)
                    }
                    // 折りたたんでも、取得の状態と操作の失敗は出し続ける
                    if !isCollapsed {
                        threads(feed)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            // 開閉のボタンと「すべて既読」は分ける（押し間違えて開閉しないように）
            DisclosureButton(isCollapsed: isCollapsed, name: account.user) {
                expansion.toggle(account.id)
            } label: {
                title
            }
            Spacer(minLength: 0)
            if status.tokenState == .ready, let feed, !feed.phase.isStopped {
                MarkAllReadButton(
                    count: feed.threads.count, newest: feed.newestUpdate, isEnabled: feed.canMarkAllRead,
                    participatingOnly: participatingOnly, isTruncated: feed.isTruncated
                ) {
                    actions.markAllRead(account.id)
                }
            }
        }
    }

    /// 見出しのうち、開閉のボタンになる部分（山形は `DisclosureButton` が付ける）。
    private var title: some View {
        HStack(spacing: 6) {
            tokenIcon
                .frame(width: 16)
            Text(account.user)
                .font(.subheadline.weight(.semibold))
            if account.isActive {
                Text("active")
                    .font(.caption)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.tint.opacity(0.15), in: Capsule())
                    .help("The active account for this host in gh")
            }
            Text("\(account.host) — \(account.hostKind.displayName)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if participatingOnly {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Showing only threads you are participating in")
                    .accessibilityLabel("Participating only")
            }
            if isCollapsed, let feed, feed.phase.showsThreads, !feed.threads.isEmpty {
                CollapsedCount(count: feed.threads.count)
            }
        }
    }

    @ViewBuilder private var tokenIcon: some View {
        switch status.tokenState {
        case .fetching:
            ProgressView().controlSize(.mini)
        case .ready where feed?.phase.isStopped == true:
            // トークンは持っているが、API に使えなかった
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                .help("Stopped")
        case .ready:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                .help("Ready")
        case .unavailable:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                .help("No token")
        case .disabled:
            Image(systemName: "pause.circle").foregroundStyle(.secondary)
                .help("Disabled")
        }
    }

    @ViewBuilder private func threads(_ feed: FeedState) -> some View {
        if feed.phase.showsThreads {
            let groups = NotificationGrouping.groups(from: feed.threads)
            let endpoints = APIEndpoints(host: account.host)
            if groups.isEmpty {
                Text("No unread notifications")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 22)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(groups) { group in
                        RepositoryGroupView(
                            group: group, account: account.id,
                            endpoints: endpoints, expansion: expansion, actions: actions)
                    }
                }
                .padding(.leading, 22)
            }
        }
    }
}

/// 通知の取得の状態と、止まっているときの案内。API のエラー出力は表示しない。
struct FeedStatusView: View {
    let account: Account
    let phase: FeedPhase
    /// 一覧を 10 ページで打ち切った（取得できた・失敗して待っているときだけ出す）
    var isTruncated = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch phase {
            case .loading:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Loading notifications…")
                }
                .foregroundStyle(.secondary)
            case .loaded(let date):
                HStack(spacing: 4) {
                    Text("Updated")
                    RelativeTimeText(date: date)
                }
                .foregroundStyle(.secondary)
            case .retrying(let nextAttempt, let rateLimited):
                Label {
                    HStack(spacing: 4) {
                        Text(rateLimited ? "Rate limited. Retrying at" : "Could not fetch notifications. Retrying at")
                        Text(nextAttempt, style: .time)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                }
            case .scopeInsufficient:
                Text(
                    "The gh token for this account has neither the repo nor the notifications scope. Add it, then reload:"
                )
                if !account.isActive {
                    CommandRow(command: "gh auth switch --hostname \(account.host) --user \(account.user)")
                }
                CommandRow(command: "gh auth refresh --hostname \(account.host) --scopes repo")
            case .unauthorized:
                Text("GitHub rejected the token from gh. Log in again, then reload:")
                CommandRow(command: "gh auth login --hostname \(account.host)")
            }
            if isTruncated, phase.showsThreads {
                Label(
                    "Showing the newest \(GitHubAPIClient.threadLimit) unread notifications. Older unread ones are not shown.",
                    systemImage: "ellipsis.circle"
                )
                .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.leading, 22)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview("Notifications") {
    let alice = Account(id: AccountID(host: "github.com", user: "alice"), isActive: true)
    let bob = Account(id: AccountID(host: "github.com", user: "bob"), isActive: false)
    let dave = Account(id: AccountID(host: "acme.ghe.com", user: "dave_acme"), isActive: true)
    let erin = Account(id: AccountID(host: "ghe.example.com", user: "erin"), isActive: true)
    let frank = Account(id: AccountID(host: "ghe.example.com", user: "frank"), isActive: false)
    let now = Date()
    func thread(_ id: String, _ repo: String, _ kind: SubjectKind, _ reason: String, minutesAgo: Double)
        -> NotificationThread?
    {
        RepositoryName(fullName: repo).map { repository in
            NotificationThread(
                id: id, reason: reason, updatedAt: now.addingTimeInterval(-minutesAgo * 60),
                title: "Make the menu bar popover remember its scroll position across openings", kind: kind,
                subjectURL: nil, repository: repository)
        }
    }
    return NotificationListView(
        statuses: [
            AccountStatus(account: alice, tokenState: .ready),
            AccountStatus(account: bob, tokenState: .ready),
            AccountStatus(account: dave, tokenState: .ready),
            AccountStatus(account: erin, tokenState: .ready),
            AccountStatus(account: frank, tokenState: .unavailable),
        ],
        feeds: [
            alice.id: FeedState(
                phase: .loaded(updatedAt: now.addingTimeInterval(-30)),
                threads: [
                    thread("1", "octo/app", .pullRequest, "review_requested", minutesAgo: 5),
                    thread("2", "octo/app", .issue, "mention", minutesAgo: 90),
                    thread("3", "octo/lib", .release, "subscribed", minutesAgo: 30),
                ].compactMap { $0 }),
            bob.id: FeedState(phase: .scopeInsufficient, threads: []),
            dave.id: FeedState(
                phase: .retrying(nextAttempt: now.addingTimeInterval(240), rateLimited: false),
                threads: [thread("4", "acme/web", .discussion, "team_mention", minutesAgo: 600)].compactMap { $0 }),
            erin.id: FeedState(phase: .unauthorized, threads: []),
        ],
        expansion: ListExpansion(), actions: .none
    )
    .padding()
    .frame(width: 380)
}

#Preview("Empty and loading") {
    let alice = Account(id: AccountID(host: "github.com", user: "alice"), isActive: true)
    let bob = Account(id: AccountID(host: "github.com", user: "bob"), isActive: false)
    let carol = Account(id: AccountID(host: "github.com", user: "carol"), isActive: false)
    return NotificationListView(
        statuses: [
            AccountStatus(account: alice, tokenState: .ready),
            AccountStatus(account: bob, tokenState: .ready),
            AccountStatus(account: carol, tokenState: .fetching),
        ],
        feeds: [
            alice.id: FeedState(phase: .loaded(updatedAt: Date()), threads: []),
            bob.id: .loading,
        ],
        expansion: ListExpansion(), actions: .none
    )
    .padding()
    .frame(width: 380)
}

#Preview("All disabled") {
    let alice = Account(id: AccountID(host: "github.com", user: "alice"), isActive: true)
    return NotificationListView(
        statuses: [AccountStatus(account: alice, tokenState: .disabled)], feeds: [:], expansion: ListExpansion(),
        actions: .none
    )
    .padding()
    .frame(width: 380)
}

#Preview("Truncated") {
    let alice = Account(id: AccountID(host: "github.com", user: "alice"), isActive: true)
    let now = Date()
    let threads = (1...3).compactMap { index in
        RepositoryName(fullName: "octo/app").map { repository in
            NotificationThread(
                id: "\(index)", reason: "subscribed", updatedAt: now.addingTimeInterval(-Double(index) * 60),
                title: "Thread \(index)", kind: .issue, subjectURL: nil, repository: repository)
        }
    }
    return NotificationListView(
        statuses: [AccountStatus(account: alice, tokenState: .ready)],
        feeds: [alice.id: FeedState(phase: .loaded(updatedAt: now), threads: threads, isTruncated: true)],
        expansion: ListExpansion(), actions: .none
    )
    .padding()
    .frame(width: 380)
}
