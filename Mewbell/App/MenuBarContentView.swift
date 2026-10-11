import AppKit
import SwiftUI

struct MenuBarContentView: View {
    let store: AccountStore
    let notifications: NotificationStore
    let permission: NotificationPermission
    let settings: AppSettings
    let expansion: ListExpansion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Mewbell")
                    .font(.headline)
                Spacer()
                OpenSettingsButton()
                ReloadButton(isLoading: store.isReloading || notifications.isRefreshing) {
                    store.reload(userInitiated: true)
                    notifications.refresh()
                }
            }

            Divider()

            if permission.isDenied {
                NotificationPermissionBanner()
            }

            if case .accounts(let statuses) = store.state {
                NotificationListView(
                    statuses: statuses, feeds: notifications.feeds, repositories: notifications.repositories,
                    participatingOnly: { settings.preferences(for: $0).participatingOnly }, expansion: expansion,
                    actions: ThreadListActions(
                        open: { notifications.open($0, in: $1) },
                        markRead: { notifications.markRead($0, in: $1) },
                        markDone: { notifications.markDone($0, in: $1) },
                        markAllRead: { notifications.markAllRead(in: $0) },
                        openWebNotifications: { notifications.openWebNotifications(for: $0) }))
            } else {
                GuidanceView(
                    state: store.state, ghExecutableOverridden: settings.ghExecutableOverride != nil,
                    ghConfigDirectoryOverridden: settings.ghConfigDirectoryOverride != nil)
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
            makePoller: nil, openURL: { _ in },
            feeds: [
                alice: FeedState(
                    phase: .loaded(updatedAt: Date()),
                    threads: (1...12).compactMap { index in
                        RepositoryName(owner: "octo", name: index.isMultiple(of: 2) ? "app" : "lib").map { repository in
                            NotificationThread(
                                id: "\(index)", reason: "subscribed",
                                updatedAt: Date().addingTimeInterval(-Double(index) * 600),
                                title: "Thread \(index)", kind: .issue, subjectURL: nil,
                                repository: repository, subjectNumber: nil)
                        }
                    })
            ]),
        permission: NotificationPermission(center: nil, authorization: .denied),
        settings: AppSettings(storage: InMemorySettingsStorage()), expansion: ListExpansion())
}

#Preview("gh not found") {
    MenuBarContentView(
        store: AccountStore(discovery: nil, state: .ghNotFound),
        notifications: NotificationStore(makePoller: nil, openURL: { _ in }),
        permission: NotificationPermission(center: nil), settings: AppSettings(storage: InMemorySettingsStorage()),
        expansion: ListExpansion())
}
