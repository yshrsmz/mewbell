import AppKit
import SwiftUI

/// 一覧での操作。`NotificationStore` に渡す。
struct ThreadListActions {
    /// スレッドがクリックされたとき（ブラウザで開いて既読にする）
    var open: (NotificationThread, AccountID) -> Void
    /// 開かずに既読にする
    var markRead: (NotificationThread, AccountID) -> Void
    var markDone: (NotificationThread, AccountID) -> Void
    /// 押したときに表示していたリポジトリのグループのスレッドを、まとめて既読・Done にする
    var markGroupRead: (RepositoryGroup, AccountID) -> Void
    var markGroupDone: (RepositoryGroup, AccountID) -> Void
    var markAllRead: (AccountID) -> Void
    /// アカウントの一覧のスレッドを、まとめて Done にする
    var markAllDone: (AccountID) -> Void
    /// アカウントのホストの Web の通知一覧をブラウザで開く（既読にはしない）
    var openWebNotifications: (AccountID) -> Void

    /// 何もしない（プレビュー用）。
    static var none: ThreadListActions {
        ThreadListActions(
            open: { _, _ in }, markRead: { _, _ in }, markDone: { _, _ in }, markGroupRead: { _, _ in },
            markGroupDone: { _, _ in }, markAllRead: { _ in }, markAllDone: { _ in },
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
    /// 一覧（`ScrollView`）の幅。ポップオーバーの幅で決まり、スクロールバーが出ても消えても変わらない
    @State private var listWidth: CGFloat?
    @State private var scrollerStyle = NSScroller.preferredScrollerStyle

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
                // スクロールバーが出ていても消えていても中身の幅を同じにし、右端のボタンを動かさない
                .frame(
                    maxWidth: ListScroller.contentWidthLimit(scrollerStyle: scrollerStyle, listWidth: listWidth),
                    alignment: .leading
                )
                // `ScrollView` は狭い中身を中央に置くので、左に寄せる
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .modifier(HidesScrollIndicatorsWhileAnimating(animations: animations))
            .environment(animations)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                listWidth = $0
            }
            // 「すべて無効」の表示の間は通知を受けないので、一覧を出すたびに読み直す
            .onAppear { scrollerStyle = NSScroller.preferredScrollerStyle }
            // マウスをつないだ・外したときや、システム設定でスクロールバーの表示を変えたときに届く
            .onReceive(
                NotificationCenter.default.publisher(for: NSScroller.preferredScrollerStyleDidChangeNotification)
            ) { _ in
                scrollerStyle = NSScroller.preferredScrollerStyle
            }
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
                subjectURL: nil, repository: repository, detailsSubject: nil)
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
                detailsSubject: nil)
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
