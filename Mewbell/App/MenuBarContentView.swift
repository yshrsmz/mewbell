import AppKit
import SwiftUI

struct MenuBarContentView: View {
    let store: AccountStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Mewbell")
                    .font(.headline)
                Spacer()
                Button {
                    store.reload(showsProgress: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(store.isReloading)
                .help("Reload gh accounts")
                .accessibilityLabel("Reload")
            }

            Divider()

            if case .accounts(let statuses) = store.state {
                AccountListView(statuses: statuses)
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
        .frame(width: 320, alignment: .leading)
        // ポップオーバーを開くたびに読み直す（ログイン直後に開けば一覧に出るように）
        .onAppear {
            store.reload()
        }
    }
}

#Preview("Accounts") {
    MenuBarContentView(
        store: AccountStore(
            discovery: nil,
            state: .accounts([
                AccountStatus(
                    account: Account(id: AccountID(host: "github.com", user: "alice"), isActive: true),
                    tokenState: .ready)
            ])))
}

#Preview("gh not found") {
    MenuBarContentView(store: AccountStore(discovery: nil, state: .ghNotFound))
}
