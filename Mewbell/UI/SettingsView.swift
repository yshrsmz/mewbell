import AppKit
import SwiftUI

/// 設定ウィンドウ。変更は `AppSettings` のメソッドで書き、すぐに反映する。トークンや API の URL、gh の出力は表示しない。
struct SettingsView: View {
    let settings: AppSettings
    let accounts: AccountStore
    let launchAtLogin: LaunchAtLogin

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView(settings: settings, launchAtLogin: launchAtLogin)
            }
            Tab("Accounts", systemImage: "person.2") {
                AccountsSettingsView(settings: settings, state: accounts.state)
            }
            Tab("gh", systemImage: "terminal") {
                GhSettingsView(settings: settings)
            }
        }
        .frame(width: 520, height: 420)
        .background(SettingsWindowActivator())
    }
}

struct GeneralSettingsView: View {
    let settings: AppSettings
    let launchAtLogin: LaunchAtLogin

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Launch at login",
                    isOn: Binding(get: { launchAtLogin.isOn }, set: { launchAtLogin.set($0) }))
                if launchAtLogin.status == .requiresApproval {
                    Text("Allow Mewbell in System Settings to finish setting it up.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Login Items Settings…") {
                        launchAtLogin.openSystemSettings()
                    }
                }
                if launchAtLogin.failed {
                    Label("Could not change the login item.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Notifications") {
                Toggle(
                    "Play a sound",
                    isOn: Binding(get: { settings.notificationSound }, set: { settings.setNotificationSound($0) }))
            }
        }
        .formStyle(.grouped)
        // システム設定で外されたときにずれないよう、開くたびに読み直す
        .onAppear { launchAtLogin.refresh() }
    }
}

struct AccountsSettingsView: View {
    let settings: AppSettings
    let state: DiscoveryState

    var body: some View {
        if state == .checking {
            ProgressView("Checking gh…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if case .accounts(let statuses) = state, !statuses.isEmpty {
            Form {
                ForEach(statuses) { status in
                    AccountSettingsSection(settings: settings, account: status.account)
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView {
                Label("No Accounts", systemImage: "person.crop.circle.badge.questionmark")
            } description: {
                Text("Mewbell could not find or read any gh accounts. Open the Mewbell menu for what to do.")
            }
        }
    }
}

struct AccountSettingsSection: View {
    let settings: AppSettings
    let account: Account

    private var preferences: AccountPreferences { settings.preferences(for: account.id) }

    var body: some View {
        Section {
            Toggle(
                "Enabled",
                isOn: Binding(
                    get: { preferences.isEnabled }, set: { settings.setEnabled($0, for: account.id) }))
            Group {
                Toggle(
                    isOn: Binding(
                        get: { preferences.participatingOnly },
                        set: { settings.setParticipatingOnly($0, for: account.id) })
                ) {
                    Text("Only threads I'm participating in")
                    Text(
                        "Mark all as read also marks threads you are not participating in, up to the newest one shown."
                    )
                }
                Toggle(
                    "Show macOS notifications",
                    isOn: Binding(get: { preferences.notifies }, set: { settings.setNotifies($0, for: account.id) }))
            }
            .disabled(!preferences.isEnabled)
        } header: {
            HStack(spacing: 6) {
                Text(account.user)
                Text("\(account.host) — \(account.hostKind.displayName)")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct GhSettingsView: View {
    let settings: AppSettings

    var body: some View {
        Form {
            Section {
                PathOverrideField(
                    title: "gh executable",
                    placeholder: "Search /opt/homebrew/bin, /usr/local/bin, then the login shell",
                    unusableMessage:
                        "Mewbell cannot use gh at this path. It must be your own executable file that others cannot modify.",
                    path: settings.ghExecutableOverride, choosesDirectories: false,
                    isUsable: { ExecutableValidator.validate($0) != nil },
                    commit: { settings.setGhExecutableOverride($0) })
            } footer: {
                Text("Enter an absolute path. Leave empty to search the usual places.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                PathOverrideField(
                    title: "gh config directory",
                    placeholder: "Uses GH_CONFIG_DIR, XDG_CONFIG_HOME/gh, or ~/.config/gh",
                    unusableMessage:
                        "Mewbell cannot use this directory. It must be your own directory that others cannot modify.",
                    path: settings.ghConfigDirectoryOverride, choosesDirectories: true,
                    isUsable: { ConfigDirectoryValidator.validate($0) != nil },
                    commit: { settings.setGhConfigDirectoryOverride($0) })
            } footer: {
                Text(
                    "Enter an absolute path (not ~/…). Set this when gh uses a different GH_CONFIG_DIR in your shell. Mewbell also passes it to gh. Changing it reloads every account."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// パスの上書きの入力。確定（Return、選択、Reset）したときだけ `commit` を呼ぶ（入力の途中では gh を探し直さない）。
struct PathOverrideField: View {
    let title: String
    let placeholder: String
    let unusableMessage: String
    /// 保存されている上書き
    let path: String?
    let choosesDirectories: Bool
    let isUsable: (String) -> Bool
    let commit: (String?) -> Void

    @State private var text = ""
    /// 保存されている上書きが使えるか（パスが変わったときだけ確かめる）
    @State private var isPathUsable = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            HStack {
                TextField(title, text: $text, prompt: Text(placeholder))
                    .labelsHidden()
                    .onSubmit {
                        commit(text)
                        // 同じパスでも確かめ直す（`path` が変わらなければ `onChange` が呼ばれないので）
                        update(SettingsKey.normalizedPath(text))
                    }
                Button("Choose…", action: choose)
                Button("Reset") {
                    text = ""
                    // 保存していない下書きを消すだけなら、読み直さない
                    if path != nil {
                        commit(nil)
                    }
                }
                .disabled(path == nil && text.isEmpty)
            }
            if SettingsKey.normalizedPath(text) != path {
                Text("Press Return to apply.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if path != nil, !isPathUsable {
                Label(unusableMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { update(path) }
        .onChange(of: path) { _, path in update(path) }
    }

    private func update(_ path: String?) {
        text = path ?? ""
        isPathUsable = path.map(isUsable) ?? true
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !choosesDirectories
        panel.canChooseDirectories = choosesDirectories
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        commit(url.path)
        // 同じパスを選び直したときも確かめ直す（`path` が変わらなければ `onChange` が呼ばれないので）
        update(url.path)
    }
}

#Preview("General") {
    GeneralSettingsView(
        settings: AppSettings(storage: InMemorySettingsStorage()),
        launchAtLogin: LaunchAtLogin(service: InertLoginItem(status: .requiresApproval))
    )
    .frame(width: 520, height: 300)
}

#Preview("Accounts") {
    let settings = AppSettings(storage: InMemorySettingsStorage())
    let alice = Account(id: AccountID(host: "github.com", user: "alice"), isActive: true)
    let bob = Account(id: AccountID(host: "github.com", user: "bob"), isActive: false)
    let dave = Account(id: AccountID(host: "acme.ghe.com", user: "dave"), isActive: true)
    settings.setEnabled(false, for: bob.id)
    settings.setParticipatingOnly(true, for: dave.id)
    return AccountsSettingsView(
        settings: settings,
        state: .accounts([
            AccountStatus(account: alice, tokenState: .ready), AccountStatus(account: bob, tokenState: .disabled),
            AccountStatus(account: dave, tokenState: .ready),
        ])
    )
    .frame(width: 520, height: 420)
}

#Preview("Accounts: not logged in") {
    AccountsSettingsView(settings: AppSettings(storage: InMemorySettingsStorage()), state: .notLoggedIn)
        .frame(width: 520, height: 300)
}

#Preview("gh") {
    let settings = AppSettings(storage: InMemorySettingsStorage())
    settings.setGhExecutableOverride("/tmp/nonexistent/gh")
    return GhSettingsView(settings: settings).frame(width: 520, height: 360)
}
