import AppKit
import SwiftUI

struct MenuBarContentView: View {
    let store: AccountStore
    let notifications: NotificationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Mewbell")
                    .font(.headline)
                Spacer()
                Button {
                    store.reload(userInitiated: true)
                    notifications.resumeStopped()
                    notifications.requestUnconditionalFetch()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(store.isReloading)
                .help("Reload gh accounts, resume stopped accounts, and fully refetch notifications on the next poll")
                .accessibilityLabel("Reload")
            }

            Divider()

            if case .accounts(let statuses) = store.state {
                NotificationListView(statuses: statuses, feeds: notifications.feeds)
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
            ]))
}

#Preview("gh not found") {
    MenuBarContentView(
        store: AccountStore(discovery: nil, state: .ghNotFound), notifications: NotificationStore(makePoller: nil))
}
