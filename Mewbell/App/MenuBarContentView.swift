import AppKit
import SwiftUI

struct MenuBarContentView: View {
    let store: AccountStore
    let notifications: NotificationStore
    let permission: NotificationPermission

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Mewbell")
                    .font(.headline)
                Spacer()
                Button {
                    store.reload(userInitiated: true)
                    // 止まっているアカウントに印を立てないよう、再開より先に呼ぶ
                    notifications.requestUnconditionalFetch()
                    notifications.resumeStopped()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(store.isReloading)
                .help("Reload gh accounts, resume stopped accounts, and fully refetch at the next poll")
                .accessibilityLabel("Reload")
            }

            Divider()

            if permission.isDenied {
                NotificationPermissionBanner()
            }

            if case .accounts(let statuses) = store.state {
                NotificationListView(
                    statuses: statuses, feeds: notifications.feeds,
                    actions: ThreadListActions(
                        open: { notifications.open($0, in: $1) },
                        markRead: { notifications.markRead($0, in: $1) },
                        markDone: { notifications.markDone($0, in: $1) },
                        markAllRead: { notifications.markAllRead(in: $0) }))
            } else {
                GuidanceView(state: store.state)
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding()
        .frame(width: 380, alignment: .leading)
        // ポップオーバーを開くたびに読み直す（ログイン直後に開けば一覧に出るように）
        .onAppear {
            store.reload()
            permission.refresh()
        }
    }
}

#Preview("Accounts") {
    let alice = AccountID(host: "github.com", user: "alice")
    MenuBarContentView(
        store: AccountStore(
            discovery: nil,
            state: .accounts([AccountStatus(account: Account(id: alice, isActive: true), tokenState: .ready)])),
        notifications: NotificationStore(
            makePoller: nil,
            feeds: [
                alice: FeedState(
                    phase: .loaded(updatedAt: Date()),
                    threads: (1...12).compactMap { index in
                        RepositoryName(owner: "octo", name: index.isMultiple(of: 2) ? "app" : "lib").map { repository in
                            NotificationThread(
                                id: "\(index)", reason: "subscribed",
                                updatedAt: Date().addingTimeInterval(-Double(index) * 600),
                                title: "Thread \(index)", kind: .issue, subjectURL: nil,
                                repository: repository)
                        }
                    })
            ]),
        permission: NotificationPermission(center: nil, authorization: .denied))
}

#Preview("gh not found") {
    MenuBarContentView(
        store: AccountStore(discovery: nil, state: .ghNotFound), notifications: NotificationStore(makePoller: nil),
        permission: NotificationPermission(center: nil))
}
