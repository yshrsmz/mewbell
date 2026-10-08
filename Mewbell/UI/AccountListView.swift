import SwiftUI

/// gh のアカウントをホストごとにまとめて表示する。トークンは表示しない。
struct AccountListView: View {
    let statuses: [AccountStatus]

    /// `statuses` の並び（ホストの順）を保ったまま、ホストごとにまとめる
    private var groups: [(host: String, statuses: [AccountStatus])] {
        var groups: [(host: String, statuses: [AccountStatus])] = []
        for status in statuses {
            if groups.last?.host == status.account.host {
                groups[groups.count - 1].statuses.append(status)
            } else {
                groups.append((status.account.host, [status]))
            }
        }
        return groups
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(groups, id: \.host) { group in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Text(group.host)
                            .font(.subheadline.weight(.semibold))
                        Text("— \(HostKind(host: group.host).displayName)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(group.statuses) { status in
                        AccountRow(status: status)
                    }
                }
            }
        }
    }
}

private struct AccountRow: View {
    let status: AccountStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                stateIcon
                    .frame(width: 16)
                Text(status.account.user)
                if status.account.isActive {
                    Text("active")
                        .font(.caption)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.tint.opacity(0.15), in: Capsule())
                        .help("The active account for this host in gh")
                }
                Spacer()
                Text(stateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if status.tokenState == .unavailable {
                Text("Could not get a token from gh. Log in again with:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                CommandRow(command: "gh auth login --hostname \(status.account.host)")
            }
        }
    }

    @ViewBuilder private var stateIcon: some View {
        switch status.tokenState {
        case .fetching:
            ProgressView().controlSize(.mini)
        case .ready:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .unavailable:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        }
    }

    private var stateText: String {
        switch status.tokenState {
        case .fetching: "Checking…"
        case .ready: "Ready"
        case .unavailable: "No token"
        }
    }
}

#Preview {
    AccountListView(statuses: [
        AccountStatus(
            account: Account(id: AccountID(host: "github.com", user: "alice"), isActive: true), tokenState: .ready),
        AccountStatus(
            account: Account(id: AccountID(host: "github.com", user: "bob"), isActive: false), tokenState: .fetching),
        AccountStatus(
            account: Account(id: AccountID(host: "acme.ghe.com", user: "dave_acme"), isActive: true), tokenState: .ready
        ),
        AccountStatus(
            account: Account(id: AccountID(host: "ghe.example.com", user: "erin"), isActive: true),
            tokenState: .unavailable),
    ])
    .padding()
    .frame(width: 320)
}
