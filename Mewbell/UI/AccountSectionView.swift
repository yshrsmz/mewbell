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
    /// アカウントのホストの Web の通知一覧をブラウザで開く（既読にはしない）
    var openWebNotifications: (AccountID) -> Void

    /// 何もしない（プレビュー用）。
    static var none: ThreadListActions {
        ThreadListActions(
            open: { _, _ in }, markRead: { _, _ in }, markDone: { _, _ in }, markAllRead: { _ in },
            openWebNotifications: { _ in })
    }
}

/// アカウントの区画をアカウントの並び順に並べる。トークンや API の URL は表示しない。
/// 無効のアカウントの区画は出さない。
struct NotificationListView: View {
    let statuses: [AccountStatus]
    let feeds: [AccountID: FeedState]
    /// アカウントごとのリポジトリのグループ（`NotificationStore` が作ったもの）
    let repositories: [AccountID: [RepositoryGroup]]
    /// 「参加しているスレッドだけにする」の設定
    var participatingOnly: (AccountID) -> Bool = { _ in false }
    /// 折りたたみの状態（アプリが 1 つだけ持つ）
    let expansion: ListExpansion
    let actions: ThreadListActions

    @State private var animations = DisclosureAnimations()

    var body: some View {
        let shown = statuses.enabled
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
                            status: status, feed: feeds[status.id], repositories: repositories[status.id] ?? [],
                            participatingOnly: participatingOnly(status.id),
                            expansion: expansion.state(for: status.id), actions: actions)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .modifier(HidesScrollIndicatorsWhileAnimating(animations: animations))
            .environment(animations)
            .frame(maxHeight: 480)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 開閉のアニメーションの間はスクロールバーを出さない。
/// 数を読むのをこの modifier に閉じ込め、開閉のたびに一覧全体が描き直されないようにする
private struct HidesScrollIndicatorsWhileAnimating: ViewModifier {
    let animations: DisclosureAnimations

    func body(content: Content) -> some View {
        content
            .scrollIndicators(animations.running > 0 ? .never : .automatic)
            // ポップオーバーを開くたびに、終わりが届かずに残った数を捨てる
            .onAppear { animations.reset() }
    }
}

/// 1 アカウントの見出し、取得の状態、リポジトリごとのスレッド。
struct AccountSectionView: View {
    let status: AccountStatus
    let feed: FeedState?
    /// このアカウントのリポジトリのグループ（並べるだけで、ここではグループ分けをしない）
    let repositories: [RepositoryGroup]
    var participatingOnly = false
    /// このアカウントの折りたたみの状態（ほかのアカウントの状態は読まない）
    let expansion: AccountExpansion
    let actions: ThreadListActions

    private var account: Account { status.account }

    var body: some View {
        let disclosure = AccountDisclosure(
            tokenState: status.tokenState, feed: feed, isStoredCollapsed: expansion.isCollapsed)
        VStack(alignment: .leading, spacing: 8) {
            header(disclosure)
            switch status.tokenState {
            case .fetching where feed == nil:
                Text("Checking gh…")
                    .foregroundStyle(.secondary)
                    .sectionNote()
            case .unavailable:
                VStack(alignment: .leading, spacing: ListLayout.noteSpacing) {
                    Text("Could not get a token from gh. Log in again with:")
                    CommandRow(command: GhCommand.login(host: account.host))
                }
                .sectionNote()
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
                    if disclosure.showsThreads && !disclosure.isCollapsed {
                        threads()
                    }
                }
            }
        }
    }

    private func header(_ disclosure: AccountDisclosure) -> some View {
        HStack(spacing: 6) {
            // 開閉のボタンと「すべて既読」は分ける（押し間違えて開閉しないように）
            DisclosureButton(
                isCollapsed: disclosure.isCollapsed, name: account.accessibilityName,
                isCollapsible: disclosure.showsThreads, count: feed?.threads.count ?? 0
            ) {
                expansion.toggle()
            } label: {
                title
            }
            Spacer(minLength: 0)
            // トークンや取得の状態にかかわらず出す（止まっていても Web では通知を見られる）
            OpenWebNotificationsButton(host: account.host) {
                actions.openWebNotifications(account.id)
            }
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
        HStack(spacing: ListLayout.spacing) {
            tokenIcon
                .frame(width: ListLayout.chevronWidth)
            // 幅が足りないときはホスト名から縮め、それでも足りなければユーザー名の末尾を省略する（active の印は省略しない）
            Text(account.user)
                .font(.headline)
                .truncatedToOneLine(account.user, mode: .tail)
                .layoutPriority(1)
            if account.isActive {
                Text("active")
                    .font(.subheadline)
                    .capsuleBadge(.tint.opacity(0.15))
                    .help("The active account for this host in gh")
            }
            Text(account.hostLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .truncatedToOneLine(account.hostLabel, mode: .middle)
            if participatingOnly {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .help("Showing only threads you are participating in")
                    .accessibilityLabel("Participating only")
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

    @ViewBuilder private func threads() -> some View {
        if repositories.isEmpty {
            Text("No unread notifications")
                .foregroundStyle(.secondary)
                .sectionNote()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(repositories) { group in
                    RepositoryGroupView(
                        group: group, account: account.id, expansion: expansion, actions: actions)
                }
            }
            .padding(.leading, ListLayout.contentIndent)
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
        VStack(alignment: .leading, spacing: ListLayout.noteSpacing) {
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
                    // 文ごとに 1 つの Text にして、時刻の途中で折り返さないようにする
                    rateLimited
                        ? Text("Rate limited. Retrying at \(nextAttempt, style: .time)")
                        : Text("Could not fetch notifications. Retrying at \(nextAttempt, style: .time)")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                }
            case .scopeInsufficient:
                Text(
                    "The gh token for this account has neither the repo nor the notifications scope. Add it, then reload:"
                )
                if !account.isActive {
                    CommandRow(command: GhCommand.switchUser(host: account.host, user: account.user))
                }
                CommandRow(command: GhCommand.refreshScopes(host: account.host))
            case .unauthorized:
                Text("GitHub rejected the token from gh. Log in again, then reload:")
                CommandRow(command: GhCommand.login(host: account.host))
            }
            if isTruncated, phase.showsThreads {
                Label(
                    "Showing the newest \(GitHubAPIClient.threadLimit) unread notifications. Older unread ones are not shown.",
                    systemImage: "ellipsis.circle"
                )
            }
        }
        .sectionNote()
    }
}

/// アカウントの見出しの開閉の状態。畳めるか・畳まれているかを 1 つの条件から決める
/// （畳んだままトークンを取れなくなったときに、山形の無い見出しに件数だけが出ないように）。
struct AccountDisclosure: Equatable {
    /// スレッドの一覧（か、未読の通知が無いことを示す表示）を出すか。畳むものはこの一覧だけなので、畳めるのもこのときだけ。
    /// トークンが「取得中」か「使える」で、取得の状態が一覧を出すとき
    let showsThreads: Bool
    /// 畳んで表示しているか（畳めないときは、畳んだ状態を覚えていても false）
    let isCollapsed: Bool

    init(tokenState: TokenState, feed: FeedState?, isStoredCollapsed: Bool) {
        showsThreads =
            switch tokenState {
            case .fetching, .ready: feed?.phase.showsThreads == true
            case .unavailable, .disabled: false
            }
        isCollapsed = showsThreads && isStoredCollapsed
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
                subjectURL: nil, repository: repository, subjectNumber: nil)
        }
    }
    let feeds: [AccountID: FeedState] = [
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
    ]
    return NotificationListView(
        statuses: [
            AccountStatus(account: alice, tokenState: .ready),
            AccountStatus(account: bob, tokenState: .ready),
            AccountStatus(account: dave, tokenState: .ready),
            AccountStatus(account: erin, tokenState: .ready),
            AccountStatus(account: frank, tokenState: .unavailable),
        ],
        feeds: feeds, repositories: feeds.mapValues { RepositoryGroup.groups(from: $0.threads) },
        expansion: ListExpansion(), actions: .none
    )
    .padding()
    .frame(width: 380)
}

#Preview("Empty and loading") {
    let alice = Account(id: AccountID(host: "github.com", user: "alice"), isActive: true)
    let bob = Account(id: AccountID(host: "github.com", user: "bob"), isActive: false)
    let carol = Account(id: AccountID(host: "github.com", user: "carol"), isActive: false)
    let feeds: [AccountID: FeedState] = [
        alice.id: FeedState(phase: .loaded(updatedAt: Date()), threads: []),
        bob.id: .loading,
    ]
    return NotificationListView(
        statuses: [
            AccountStatus(account: alice, tokenState: .ready),
            AccountStatus(account: bob, tokenState: .ready),
            AccountStatus(account: carol, tokenState: .fetching),
        ],
        feeds: feeds, repositories: feeds.mapValues { RepositoryGroup.groups(from: $0.threads) },
        expansion: ListExpansion(), actions: .none
    )
    .padding()
    .frame(width: 380)
}

#Preview("All disabled") {
    let alice = Account(id: AccountID(host: "github.com", user: "alice"), isActive: true)
    return NotificationListView(
        statuses: [AccountStatus(account: alice, tokenState: .disabled)], feeds: [:], repositories: [:],
        expansion: ListExpansion(), actions: .none
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
                title: "Thread \(index)", kind: .issue, subjectURL: nil, repository: repository,
                subjectNumber: nil)
        }
    }
    let feeds = [alice.id: FeedState(phase: .loaded(updatedAt: now), threads: threads, isTruncated: true)]
    return NotificationListView(
        statuses: [AccountStatus(account: alice, tokenState: .ready)], feeds: feeds,
        repositories: feeds.mapValues { RepositoryGroup.groups(from: $0.threads) },
        expansion: ListExpansion(), actions: .none
    )
    .padding()
    .frame(width: 380)
}
