import AppKit
import SwiftUI

/// 設定ウィンドウ。変更は `AppSettings` のメソッドで書き、すぐに反映する。トークンや API の URL、gh の出力は表示しない。
/// store を受け取るのはこの View だけで、タブの中身には値と `SettingsActions` を渡す。
struct SettingsView: View {
    let settings: AppSettings
    let accounts: AccountStore
    let notifications: NotificationStore
    let launchAtLogin: LaunchAtLogin

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView(
                    notificationSound: settings.notificationSound, launchAtLoginStatus: launchAtLogin.status,
                    launchAtLoginIsOn: launchAtLogin.isOn, launchAtLoginFailed: launchAtLogin.failed, actions: actions)
            }
            Tab("Accounts", systemImage: "person.2") {
                AccountsSettingsView(
                    state: accounts.state, preferences: { settings.preferences(for: $0) }, actions: actions)
            }
            Tab("gh", systemImage: "terminal") {
                GhSettingsView(
                    executableOverride: settings.ghExecutableOverride,
                    configDirectoryOverride: settings.ghConfigDirectoryOverride, actions: actions)
            }
            Tab("Diagnostics", systemImage: "stethoscope") {
                DiagnosticsSettingsView(report: diagnosticsReport)
            }
        }
        .frame(width: 520, height: 420)
        .background(SettingsWindowActivator())
    }

    private var actions: SettingsActions {
        SettingsActions(
            setNotificationSound: { settings.setNotificationSound($0) },
            setLaunchAtLogin: { launchAtLogin.set($0) },
            openLoginItemsSettings: { launchAtLogin.openSystemSettings() },
            refreshLaunchAtLogin: { launchAtLogin.refresh() },
            setEnabled: { settings.setEnabled($0, for: $1) },
            setParticipatingOnly: { settings.setParticipatingOnly($0, for: $1) },
            setNotifies: { settings.setNotifies($0, for: $1) },
            setGhExecutableOverride: { settings.setGhExecutableOverride($0) },
            setGhConfigDirectoryOverride: { settings.setGhConfigDirectoryOverride($0) },
            // `applicationShouldTerminate` の後片付け（ポーリングの停止とトークンの破棄）を通す
            quit: { NSApp.terminate(nil) })
    }

    /// Diagnostics タブの報告。`DiagnosticsSettingsView` の body で呼ばれ、ポーリングのたびに変わる値はそこで読まれる。
    private func diagnosticsReport() -> DiagnosticsReport {
        DiagnosticsReport(
            ghDetection: accounts.ghDetection, state: accounts.state,
            accounts: DiagnosticsReport.accounts(in: accounts.state, feeds: notifications.feeds) {
                settings.preferences(for: $0)
            },
            appVersion: Self.appVersion, osVersion: Self.osVersion)
    }

    // 起動中は変わらないので 1 回だけ読む（一覧が変わるたびに report を作り直すため）
    private static let appVersion: String = {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        // CFBundleVersion は MARKETING_VERSION と同じ値にしている（release-please が上げる）ので、違うときだけ添える
        return build == version ? version : "\(version) (\(build))"
    }()

    private static let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
}

/// 設定ウィンドウでの操作。`SettingsView` が `AppSettings` と `LaunchAtLogin` のメソッドにつなぐ。
struct SettingsActions {
    var setNotificationSound: (Bool) -> Void
    /// ログイン時に起動するかを切り替える
    var setLaunchAtLogin: (Bool) -> Void
    /// システム設定のログイン項目を開く
    var openLoginItemsSettings: () -> Void
    /// ログイン項目の登録の状態を macOS から読み直す
    var refreshLaunchAtLogin: () -> Void
    var setEnabled: (Bool, AccountID) -> Void
    var setParticipatingOnly: (Bool, AccountID) -> Void
    var setNotifies: (Bool, AccountID) -> Void
    /// gh の実行ファイルの上書きを確定する（nil で上書きを外す）
    var setGhExecutableOverride: (String?) -> Void
    /// gh の設定ディレクトリの上書きを確定する（nil で上書きを外す）
    var setGhConfigDirectoryOverride: (String?) -> Void
    /// アプリを終了する（メニューバーのアイコンの右クリックのメニューを出せないときの終了の手段）
    var quit: () -> Void

    /// 何もしない（プレビュー用）。
    static var none: SettingsActions {
        SettingsActions(
            setNotificationSound: { _ in }, setLaunchAtLogin: { _ in }, openLoginItemsSettings: {},
            refreshLaunchAtLogin: {}, setEnabled: { _, _ in }, setParticipatingOnly: { _, _ in },
            setNotifies: { _, _ in }, setGhExecutableOverride: { _ in }, setGhConfigDirectoryOverride: { _ in },
            quit: {})
    }
}

struct GeneralSettingsView: View {
    let notificationSound: Bool
    let launchAtLoginStatus: LoginItemStatus
    /// 登録されている（承認待ちを含む）
    let launchAtLoginIsOn: Bool
    /// 直前の登録・解除に失敗した
    let launchAtLoginFailed: Bool
    let actions: SettingsActions

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Launch at login",
                    isOn: Binding(get: { launchAtLoginIsOn }, set: { actions.setLaunchAtLogin($0) }))
                if launchAtLoginStatus == .requiresApproval {
                    Text("Allow Mewbell in System Settings to finish setting it up.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Login Items Settings…") {
                        actions.openLoginItemsSettings()
                    }
                }
                if launchAtLoginFailed {
                    Label("Could not change the login item.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Notifications") {
                Toggle(
                    "Play a sound",
                    isOn: Binding(get: { notificationSound }, set: { actions.setNotificationSound($0) }))
            }
            Section {
                Button("Quit Mewbell", action: actions.quit)
            }
        }
        .formStyle(.grouped)
        // システム設定で外されたときにずれないよう、開くたびに読み直す
        .onAppear { actions.refreshLaunchAtLogin() }
    }
}

struct AccountsSettingsView: View {
    let state: DiscoveryState
    /// アカウントごとの設定（この View の body で読み、設定を変えたときに描き直すのをこのタブの中にとどめる）
    let preferences: (AccountID) -> AccountPreferences
    let actions: SettingsActions

    var body: some View {
        if state == .checking {
            ProgressView("Checking gh…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if case .accounts(let statuses) = state, !statuses.isEmpty {
            Form {
                ForEach(statuses) { status in
                    AccountSettingsSection(
                        account: status.account, preferences: preferences(status.account.id), actions: actions)
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
    let account: Account
    let preferences: AccountPreferences
    let actions: SettingsActions

    var body: some View {
        Section {
            Toggle(
                "Enabled",
                isOn: Binding(get: { preferences.isEnabled }, set: { actions.setEnabled($0, account.id) }))
            Group {
                Toggle(
                    isOn: Binding(
                        get: { preferences.participatingOnly },
                        set: { actions.setParticipatingOnly($0, account.id) })
                ) {
                    Text("Only threads I'm participating in")
                    Text(
                        "Mark all as read also marks threads you are not participating in, up to the newest one shown."
                    )
                }
                Toggle(
                    "Show macOS notifications",
                    isOn: Binding(get: { preferences.notifies }, set: { actions.setNotifies($0, account.id) }))
            }
            .disabled(!preferences.isEnabled)
        } header: {
            HStack(spacing: 6) {
                Text(account.user)
                Text(account.hostLabel)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct GhSettingsView: View {
    let executableOverride: String?
    let configDirectoryOverride: String?
    let actions: SettingsActions

    var body: some View {
        Form {
            Section {
                PathOverrideField(
                    title: "gh executable",
                    placeholder: "Search /opt/homebrew/bin, /usr/local/bin, then the login shell",
                    unusableMessage:
                        "Mewbell cannot use gh at this path. It must be your own executable file that others cannot modify.",
                    path: executableOverride, choosesDirectories: false,
                    isUsable: { ExecutableValidator.validate($0) != nil },
                    commit: actions.setGhExecutableOverride)
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
                    path: configDirectoryOverride, choosesDirectories: true,
                    isUsable: { ConfigDirectoryValidator.validate($0) != nil },
                    commit: actions.setGhConfigDirectoryOverride)
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
        notificationSound: true, launchAtLoginStatus: .requiresApproval, launchAtLoginIsOn: true,
        launchAtLoginFailed: false, actions: .none
    )
    .frame(width: 520, height: 300)
}

#Preview("Accounts") {
    let alice = Account(id: AccountID(host: "github.com", user: "alice"), isActive: true)
    let bob = Account(id: AccountID(host: "github.com", user: "bob"), isActive: false)
    let dave = Account(id: AccountID(host: "acme.ghe.com", user: "dave"), isActive: true)
    return AccountsSettingsView(
        state: .accounts([
            AccountStatus(account: alice, tokenState: .ready), AccountStatus(account: bob, tokenState: .disabled),
            AccountStatus(account: dave, tokenState: .ready),
        ]),
        preferences: { AccountPreferences(isEnabled: $0 != bob.id, participatingOnly: $0 == dave.id) },
        actions: .none
    )
    .frame(width: 520, height: 420)
}

#Preview("Accounts: not logged in") {
    AccountsSettingsView(state: .notLoggedIn, preferences: { _ in .default }, actions: .none)
        .frame(width: 520, height: 300)
}

#Preview("gh") {
    GhSettingsView(executableOverride: "/tmp/nonexistent/gh", configDirectoryOverride: nil, actions: .none)
        .frame(width: 520, height: 360)
}
