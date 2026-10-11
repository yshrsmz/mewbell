import AppKit
import SwiftUI

/// アカウント一覧を出せないときの案内。gh や API のエラー出力は表示しない。
struct GuidanceView: View {
    /// 固定の URL だけを開く（外部から受け取った URL は開かない）
    private static let ghWebsite = URL(string: "https://cli.github.com/")

    let state: DiscoveryState
    /// 設定で gh のパスを上書きしている（見つからないときは、インストールではなく設定を案内する）
    var ghExecutableOverridden = false
    /// 設定で gh の設定ディレクトリを上書きしている
    var ghConfigDirectoryOverridden = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch state {
            case .checking:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking gh…")
                        .foregroundStyle(.secondary)
                }
            case .ghNotFound where ghExecutableOverridden:
                title("Cannot use the gh set in Settings", systemImage: "exclamationmark.triangle")
                Text("The gh executable set in Settings is missing or not safe to run. Change or reset it in Settings.")
                OpenSettingsButton(style: .text)
            case .ghNotFound:
                title("gh is not installed", systemImage: "exclamationmark.triangle")
                Text("Mewbell uses the accounts you have logged in to with the GitHub CLI. Install it, then log in.")
                CommandRow(command: GhCommand.install)
                if let ghWebsite = Self.ghWebsite {
                    Button("Open cli.github.com") {
                        NSWorkspace.shared.open(ghWebsite)
                    }
                }
            case .ghOutdated(let version):
                title("gh is too old", systemImage: "exclamationmark.triangle")
                Text(
                    "Found gh \(version.description). Mewbell needs gh \(GhVersion.minimumSupported.description) or later."
                )
                CommandRow(command: GhCommand.upgrade)
            case .ghUnavailable:
                title("Could not run gh", systemImage: "exclamationmark.triangle")
                Text("gh did not respond as expected. Check that this command works, then reload.")
                CommandRow(command: GhCommand.version)
            case .hostsFileUnreadable(let path):
                title("Cannot read gh's account list", systemImage: "exclamationmark.triangle")
                Text("Could not read \(path). Check your gh login with:")
                CommandRow(command: GhCommand.status)
                if ghConfigDirectoryOverridden {
                    Text("This path comes from the gh config directory set in Settings.")
                    OpenSettingsButton(style: .text)
                }
            case .notLoggedIn:
                title("Not logged in to gh", systemImage: "person.crop.circle.badge.questionmark")
                Text("Log in with the GitHub CLI. For GitHub Enterprise, add --hostname <host>.")
                CommandRow(command: GhCommand.login())
            case .accounts:
                EmptyView()
            }
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func title(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.headline)
    }
}

#Preview("Checking") {
    GuidanceView(state: .checking).padding().frame(width: 320)
}

#Preview("gh not found") {
    GuidanceView(state: .ghNotFound).padding().frame(width: 320)
}

#Preview("gh outdated") {
    GuidanceView(state: .ghOutdated(version: GhVersion(major: 2, minor: 39, patch: 2))).padding().frame(width: 320)
}

#Preview("gh unavailable") {
    GuidanceView(state: .ghUnavailable).padding().frame(width: 320)
}

#Preview("hosts.yml unreadable") {
    GuidanceView(state: .hostsFileUnreadable(path: "/Users/me/.config/gh/hosts.yml")).padding().frame(width: 320)
}

#Preview("Not logged in") {
    GuidanceView(state: .notLoggedIn).padding().frame(width: 320)
}

#Preview("Overridden gh not usable") {
    GuidanceView(state: .ghNotFound, ghExecutableOverridden: true).padding().frame(width: 320)
}

#Preview("Overridden config directory not readable") {
    GuidanceView(state: .hostsFileUnreadable(path: "/Users/me/.gh-old/hosts.yml"), ghConfigDirectoryOverridden: true)
        .padding().frame(width: 320)
}
