import SwiftUI

/// アカウントの見出し。開閉のボタンの上に、マウスを載せている間か確認の表示の間だけ、Web の通知一覧・すべて既読・
/// すべて Done のボタンを重ねる（リポジトリの見出しと同じ）。同じ操作をコンテキストメニューと VoiceOver の操作にも出す。
struct AccountHeadingView: View {
    let status: AccountStatus
    let feed: FeedState?
    let disclosure: AccountDisclosure
    let participatingOnly: Bool
    /// このアカウントの折りたたみの状態
    let expansion: AccountExpansion
    let actions: ThreadListActions

    /// 確認の表示にしている見出しのボタン。すべて既読とすべて Done を同時に確認の表示にしないよう、1 つの値で持つ
    @State private var confirming: AccountHeadingAction?
    @State private var isHovering = false
    /// 重ねたボタンの幅（見出しの中身をその手前で省略する）
    @State private var actionsWidth: CGFloat = 0

    private var account: Account { status.account }

    /// 確認の表示はマウスを外しても出し続ける
    private var showsActions: Bool { isHovering || confirming != nil }

    /// すべて既読とすべて Done を出すときの取得の状態（トークンが使えて、止まっていないとき）。出さないときは nil
    private var markAllFeed: FeedState? {
        guard status.tokenState == .ready, let feed, !feed.phase.isStopped else { return nil }
        return feed
    }

    var body: some View {
        // 操作のボタンは開閉のボタンの中に入れず、上に重ねる（見出しのクリックと奪い合わないように。リポジトリの見出しと同じ）
        DisclosureButton(
            isCollapsed: disclosure.isCollapsed, name: account.displayName,
            isCollapsible: disclosure.showsThreads, count: feed?.threads.count ?? 0, isHovering: isHovering,
            trailingInset: showsActions ? actionsWidth : 0
        ) {
            expansion.toggle()
        } icon: {
            tokenIcon
                .frame(width: ListLayout.iconColumnWidth)
        } label: {
            title
        }
        // ホバーのボタンを使えない VoiceOver でも操作できるように（すべて既読とすべて Done は確認の表示にするだけ）
        .accessibilityActions {
            Button(OpenWebNotificationsButton.label(for: account.host), action: openWebNotifications)
            if let feed = markAllFeed, feed.canMarkAll {
                Button(MarkAllReadLabels.read) {
                    announceConfirming(
                        .markAllRead, label: markAllReadLabels(feed).accessibilityLabel(confirming: true))
                }
                Button(MarkAllDoneLabels.done) {
                    announceConfirming(
                        .markAllDone,
                        label: MarkAllDoneLabels(count: feed.threads.count).accessibilityLabel(confirming: true))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // 並びと間隔は、リポジトリの見出しの「既読にする」「Done にする」に合わせる
        .headingActions(isShown: showsActions, width: $actionsWidth) { actionButtons }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Open Notifications in Browser", action: openWebNotifications)
            if markAllFeed != nil {
                Button("Mark All as Read") { startConfirming(.markAllRead) }
                    .disabled(!canMarkAll)
                Button("Mark All as Done") { startConfirming(.markAllDone) }
                    .disabled(!canMarkAll)
            }
        }
    }

    /// すべて既読とすべて Done を押せるか
    private var canMarkAll: Bool { markAllFeed?.canMarkAll == true }

    /// コンテキストメニューと VoiceOver の操作から確認の表示にする。メニューを開いている間に押せなくなっていたら何もしない
    private func startConfirming(_ action: AccountHeadingAction) {
        guard canMarkAll else { return }
        confirming = action
    }

    /// 見出しに重ねる操作のボタン
    @ViewBuilder private var actionButtons: some View {
        // トークンや取得の状態にかかわらず出す（止まっていても Web では通知を見られる）
        OpenWebNotificationsButton(host: account.host, action: openWebNotifications)
        if let feed = markAllFeed {
            MarkAllReadButton(
                confirming: confirmingBinding(.markAllRead), labels: markAllReadLabels(feed),
                newest: feed.newestUpdate, isEnabled: feed.canMarkAll
            ) {
                actions.markAllRead(account.id)
            }
            MarkAllDoneButton(
                confirming: confirmingBinding(.markAllDone), threadIDs: feed.threads.map(\.id),
                isEnabled: feed.canMarkAll
            ) {
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
        guard canMarkAll else { return }
        startConfirming(action)
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

    /// 見出しの文字（山形とトークンの状態のアイコンは `DisclosureButton` が中央に置く）。
    /// 大きさの違う文字（13pt のユーザー名と 11pt のホスト名など）をベースラインで揃える
    private var title: some View {
        HStack(alignment: .firstTextBaseline, spacing: ListLayout.spacing) {
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
}

/// アカウントの見出しの、確認の表示にするボタン。
private enum AccountHeadingAction {
    case markAllRead
    case markAllDone
}
