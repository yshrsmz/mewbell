import AppKit
import SwiftUI

/// アカウントの区画をアカウントの並び順に並べる。トークンや API の URL は表示しない。
struct NotificationListView: View {
    let statuses: [AccountStatus]
    let feeds: [AccountID: FeedState]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(statuses) { status in
                    AccountSectionView(status: status, feed: feeds[status.id])
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 1 アカウントの見出し、取得の状態、リポジトリごとのスレッド。
struct AccountSectionView: View {
    let status: AccountStatus
    let feed: FeedState?

    private var account: Account { status.account }

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
            case .fetching, .ready:
                // 401 の後などにトークンを取り直している間も、それまでの状態を出し続ける
                if let feed {
                    FeedStatusView(account: account, phase: feed.phase)
                    threads(feed)
                }
            }
        }
    }

    private var header: some View {
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
            Spacer(minLength: 0)
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
        }
    }

    @ViewBuilder private func threads(_ feed: FeedState) -> some View {
        switch feed.phase {
        case .loaded, .retrying:
            let groups = NotificationGrouping.groups(from: feed.threads)
            if groups.isEmpty {
                Text("No unread notifications")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 22)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.repository.description)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(group.threads) { thread in
                                ThreadRow(thread: thread) { open(thread) }
                            }
                        }
                    }
                }
                .padding(.leading, 22)
            }
        case .loading, .scopeInsufficient, .unauthorized:
            EmptyView()
        }
    }

    /// Web の URL を組み立て、アカウントのホストの `https` のときだけ開く。
    private func open(_ thread: NotificationThread) {
        guard let endpoints = APIEndpoints(host: account.host),
            let url = ThreadWebURL.make(for: thread, endpoints: endpoints)
        else { return }
        NSWorkspace.shared.open(url)
    }
}

/// スレッドの行。クリックでブラウザで開く。
struct ThreadRow: View {
    let thread: NotificationThread
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(thread.title)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 4) {
                        Text(NotificationGrouping.reasonText(thread.reason))
                        Text("·")
                        RelativeTimeText(date: thread.updatedAt)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .help("Open in browser")
    }

    private var symbol: String {
        switch thread.kind {
        case .pullRequest: "arrow.triangle.pull"
        case .issue: "smallcircle.filled.circle"
        case .commit: "point.3.connected.trianglepath.dotted"
        case .release: "tag"
        case .discussion: "bubble.left.and.bubble.right"
        case .checkSuite, .other: "bell"
        }
    }
}

/// 「5 min. ago」のような相対時刻。ポップオーバーを開いている間も 30 秒ごとに更新する。
private struct RelativeTimeText: View {
    let date: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            // 文字列にしてから渡す（時刻が進むと文字列が変わり、描き直される）
            Text(date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
        }
    }
}

/// 通知の取得の状態と、止まっているときの案内。API のエラー出力は表示しない。
struct FeedStatusView: View {
    let account: Account
    let phase: FeedPhase

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
        ]
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
        ]
    )
    .padding()
    .frame(width: 380)
}
