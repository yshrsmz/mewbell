import AppKit
import SwiftUI

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
                    CommandRow(command: GhCommand.relogin(for: account.id))
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
                        ActionFailureView(failure: failure, account: account)
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
                isCollapsed: disclosure.isCollapsed, name: account.displayName,
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
                .frame(width: ListLayout.iconColumnWidth)
            // 幅が足りないときはホスト名から縮め、それでも足りなければユーザー名の末尾を省略する（active の印は省略しない）
            OneLineText(text: account.user, truncation: .tail)
                .font(.headline)
                .layoutPriority(1)
            if account.isActive {
                Text("active")
                    .font(.subheadline)
                    .capsuleBadge(.tint.opacity(0.15))
                    .help("The active account for this host in gh")
            }
            OneLineText(text: account.hostLabel, truncation: .middle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if participatingOnly {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .help("Showing only threads you are participating in")
                    .accessibilityLabel("Participating only")
            }
        }
    }

    /// 名前は記号の既定の名前の代わりに読ませ、ツールチップにも出す
    private var tokenIcon: some View {
        let icon = TokenStateIcon(tokenState: status.tokenState, phase: feed?.phase)
        return Group {
            if let symbol = icon.symbol {
                Image(systemName: symbol)
                    .foregroundStyle(icon.color.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
            } else {
                ProgressView().controlSize(.mini)
            }
        }
        .help(icon.label)
        .accessibilityLabel(icon.label)
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
                    CommandRow(command: GhCommand.switchUser(to: account.id))
                }
                CommandRow(command: GhCommand.refreshScopes(for: account.id))
            case .unauthorized:
                Text("GitHub rejected the token from gh. Log in again, then reload:")
                CommandRow(command: GhCommand.relogin(for: account.id))
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
