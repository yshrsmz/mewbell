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

    /// 確認の表示にしている見出しのボタン。すべて既読とすべて Done を同時に確認の表示にしないよう、1 つの値で持つ
    @State private var confirming: AccountHeadingAction?
    @State private var isHovering = false
    /// 重ねたボタンの幅（見出しの中身をその手前で省略する）
    @State private var actionsWidth: CGFloat = 0

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

    /// 確認の表示はマウスを外しても出し続ける
    private var showsActions: Bool { isHovering || confirming != nil }

    /// すべて既読とすべて Done を出すときの取得の状態（トークンが使えて、止まっていないとき）。出さないときは nil
    private var markAllFeed: FeedState? {
        guard status.tokenState == .ready, let feed, !feed.phase.isStopped else { return nil }
        return feed
    }

    private func header(_ disclosure: AccountDisclosure) -> some View {
        // 操作のボタンは開閉のボタンの中に入れず、上に重ねる（見出しのクリックと奪い合わないように。リポジトリの見出しと同じ）
        DisclosureButton(
            isCollapsed: disclosure.isCollapsed, name: account.displayName,
            isCollapsible: disclosure.showsThreads, count: feed?.threads.count ?? 0, isHovering: isHovering,
            trailingInset: showsActions ? actionsWidth : 0
        ) {
            expansion.toggle()
        } label: {
            title
        }
        // ホバーのボタンを使えない VoiceOver でも操作できるように（すべて既読とすべて Done は確認の表示にするだけ）
        .accessibilityActions {
            Button(OpenWebNotificationsButton.label(for: account.host), action: openWebNotifications)
            if let feed = markAllFeed {
                if feed.canMarkAllRead {
                    Button(MarkAllReadLabels.read) {
                        announceConfirming(
                            .markAllRead, label: markAllReadLabels(feed).accessibilityLabel(confirming: true))
                    }
                }
                if !feed.threads.isEmpty {
                    Button(MarkAllDoneLabels.done) {
                        announceConfirming(
                            .markAllDone,
                            label: MarkAllDoneLabels(count: feed.threads.count).accessibilityLabel(confirming: true))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // 並びと間隔は、リポジトリの見出しの「既読にする」「Done にする」に合わせる
        .headingActions(isShown: showsActions, width: $actionsWidth) { actionButtons }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Open Notifications in Browser", action: openWebNotifications)
            if let feed = markAllFeed {
                Button("Mark All as Read") { confirming = .markAllRead }
                    .disabled(!feed.canMarkAllRead)
                Button("Mark All as Done") { confirming = .markAllDone }
                    .disabled(feed.threads.isEmpty)
            }
        }
    }

    /// 見出しに重ねる操作のボタン
    @ViewBuilder private var actionButtons: some View {
        // トークンや取得の状態にかかわらず出す（止まっていても Web では通知を見られる）
        OpenWebNotificationsButton(host: account.host, action: openWebNotifications)
        if let feed = markAllFeed {
            MarkAllReadButton(
                confirming: confirmingBinding(.markAllRead), labels: markAllReadLabels(feed),
                newest: feed.newestUpdate, isEnabled: feed.canMarkAllRead
            ) {
                actions.markAllRead(account.id)
            }
            MarkAllDoneButton(confirming: confirmingBinding(.markAllDone), threadIDs: feed.threads.map(\.id)) {
                actions.markAllDone(account.id)
            }
        }
    }

    private func openWebNotifications() {
        actions.openWebNotifications(account.id)
    }

    /// すべて既読のボタンの文（ボタンと VoiceOver の読み上げで同じものを使う）
    private func markAllReadLabels(_ feed: FeedState) -> MarkAllReadLabels {
        MarkAllReadLabels(
            count: feed.threads.count, participatingOnly: participatingOnly, isTruncated: feed.isTruncated)
    }

    /// VoiceOver の操作から確認の表示にする。見出しの表示が変わるだけでは何も読まれないので、確認を待っていることを
    /// `label`（確認の表示のボタンの読み上げ）で知らせる
    private func announceConfirming(_ action: AccountHeadingAction, label: String) {
        confirming = action
        AccessibilityNotification.Announcement(label).post()
    }

    /// 1 つのボタンの確認の状態。true にすると、もう一方のボタンの確認は解ける
    private func confirmingBinding(_ action: AccountHeadingAction) -> Binding<Bool> {
        Binding {
            confirming == action
        } set: { isConfirming in
            if isConfirming {
                confirming = action
            } else if confirming == action {
                confirming = nil
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
            OneLineText(text: account.host, truncation: .middle)
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

/// アカウントの見出しの、確認の表示にするボタン。
private enum AccountHeadingAction {
    case markAllRead
    case markAllDone
}
