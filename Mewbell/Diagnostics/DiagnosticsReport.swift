import Foundation

/// Diagnostics タブの表示とコピーの中身。トークン、API の URL、スレッドの件名、gh や API の生の出力は入れない
/// （入力の `FeedState` からは件数と診断の値だけを読む）。
struct DiagnosticsReport: Sendable, Equatable {
    struct Row: Sendable, Equatable, Identifiable {
        let label: String
        /// 値の文。nil で `time` も無ければ値が分からない（`time` だけなら時刻だけを出す）
        let text: String?
        /// 値に添える時刻
        var time: Date?

        var id: String { label }
    }

    struct Section: Sendable, Equatable, Identifiable {
        let title: String
        let rows: [Row]

        var id: String { title }
    }

    /// アカウントごとの入力。
    struct AccountInput: Sendable {
        let status: AccountStatus
        let preferences: AccountPreferences
        /// ポーリングしていなければ nil
        let feed: FeedState?
    }

    static let unknown = "Unknown"

    let sections: [Section]

    init(
        ghDetection: GhDiagnostics, state: DiscoveryState, accounts: [AccountInput], appName: String,
        appVersion: String, osVersion: String
    ) {
        sections =
            [
                Section(
                    title: appName,
                    rows: [Row(label: "Version", text: appVersion), Row(label: "macOS", text: osVersion)]),
                Self.ghSection(ghDetection, state: state),
            ] + accounts.map(Self.accountSection)
    }

    /// `state` が「アカウントあり」なら、その並び順で `feeds` と `preferences` を合わせる（無効のアカウントも含める）。
    static func accounts(
        in state: DiscoveryState, feeds: [AccountID: FeedState], preferences: (AccountID) -> AccountPreferences
    ) -> [AccountInput] {
        guard case .accounts(let statuses) = state else { return [] }
        return statuses.map { AccountInput(status: $0, preferences: preferences($0.id), feed: feeds[$0.id]) }
    }

    /// コピーするテキスト。時刻は ISO 8601（UTC）にし、トークンらしい文字列は伏せ字にする。
    var plainText: String {
        let format = Date.ISO8601FormatStyle(includingFractionalSeconds: false, timeZone: .gmt)
        let body = sections.map { section in
            let rows = section.rows.map { row in
                let time = row.time.map { $0.formatted(format) }
                let value =
                    switch (row.text, time) {
                    case (let text?, let time?): "\(text) (\(time))"
                    case (let text?, nil): text
                    case (nil, let time?): time
                    case (nil, nil): Self.unknown
                    }
                return "\(row.label): \(value)"
            }
            return (["[\(section.title)]"] + rows).joined(separator: "\n")
        }
        return Redaction.redactTokens(in: "Mewbell Diagnostics\n\n" + body.joined(separator: "\n\n") + "\n")
    }

    private static func ghSection(_ detection: GhDiagnostics, state: DiscoveryState) -> Section {
        let version = detection.version.map { version in
            version.isSupported
                ? "\(version) (supported)" : "\(version) (older than \(GhVersion.minimumSupported), not supported)"
        }
        return Section(
            title: "gh",
            rows: [
                Row(label: "Status", text: describe(state)),
                Row(label: "Executable", text: detection.executable?.url.path),
                Row(label: "Found via", text: detection.executable.map { describe($0.source) }),
                Row(label: "Version", text: version),
                Row(label: "Config directory", text: detection.configDirectory?.url.path),
                Row(label: "Config directory from", text: detection.configDirectory.map { describe($0.source) }),
            ])
    }

    private static func accountSection(_ input: AccountInput) -> Section {
        let account = input.status.account
        var rows = [
            Row(label: "Host kind", text: account.hostKind.displayName),
            Row(label: "Active in gh", text: account.isActive ? "Yes" : "No"),
            Row(label: "Token", text: describe(input.status.tokenState)),
            Row(label: "Participating only", text: input.preferences.participatingOnly ? "On" : "Off"),
            Row(label: "macOS notifications", text: input.preferences.notifies ? "On" : "Off"),
        ]
        guard let feed = input.feed else {
            rows.append(Row(label: "Fetch", text: "Not polling"))
            return Section(title: account.id.description, rows: rows)
        }
        let diagnostics = feed.diagnostics
        let interval = diagnostics.pollInterval.map {
            "\($0.seconds) s (\($0.fromHeader ? "X-Poll-Interval" : "default"))"
        }
        let scopes = diagnostics.scopes.map { scopes in
            scopes.scopes.map { $0.isEmpty ? "(none)" : $0.sorted().joined(separator: ", ") } ?? "(no header)"
        }
        rows += [
            Row(label: "Fetch", text: describe(feed.phase)),
            Row(label: "Last fetched", text: nil, time: diagnostics.lastFetchedAt),
            Row(
                label: "Next fetch", text: diagnostics.nextFetchAt == nil ? "Not scheduled" : nil,
                time: diagnostics.nextFetchAt),
            Row(label: "Poll interval", text: interval),
            Row(label: "Scopes", text: scopes),
            Row(
                label: "Unread",
                text: feed.isTruncated ? "\(feed.threads.count) (stopped at 10 pages)" : "\(feed.threads.count)"),
            Row(
                label: "Last fetch failure", text: diagnostics.lastFetchFailure.map { describe($0.kind) } ?? "None",
                time: diagnostics.lastFetchFailure?.occurredAt),
            Row(
                label: "Last action failure",
                text: diagnostics.lastActionFailure.map { "\(describe($0.action)): \(describe($0.kind))" } ?? "None",
                time: diagnostics.lastActionFailure?.occurredAt),
        ]
        return Section(title: account.id.description, rows: rows)
    }

    private static func describe(_ state: DiscoveryState) -> String {
        switch state {
        case .checking: "Checking"
        case .ghNotFound: "gh not found"
        case .ghOutdated: "gh is too old"
        case .ghUnavailable: "gh could not run"
        case .hostsFileUnreadable: "Cannot read hosts.yml"
        case .notLoggedIn: "Not logged in"
        case .accounts(let statuses): statuses.count == 1 ? "1 account" : "\(statuses.count) accounts"
        }
    }

    private static func describe(_ source: GhExecutableSource) -> String {
        switch source {
        case .override: "Settings override"
        case .standardLocation: "Standard location"
        case .loginShell: "Login shell"
        }
    }

    private static func describe(_ source: GhConfigDirectory.Source) -> String {
        switch source {
        case .override: "Settings override"
        case .ghConfigDir: "GH_CONFIG_DIR"
        case .xdgConfigHome: "XDG_CONFIG_HOME"
        case .defaultLocation: "Default"
        }
    }

    private static func describe(_ state: TokenState) -> String {
        switch state {
        case .fetching: "Fetching"
        case .ready: "Ready"
        case .unavailable: "Unavailable"
        case .disabled: "Disabled"
        }
    }

    private static func describe(_ phase: FeedPhase) -> String {
        switch phase {
        case .loading: "Loading"
        case .loaded: "Loaded"
        case .retrying(_, rateLimited: true): "Rate limited, waiting"
        case .retrying: "Failed, waiting to retry"
        case .scopeInsufficient: "Stopped: missing the repo and notifications scopes"
        case .unauthorized: "Stopped: unauthorized"
        }
    }

    private static func describe(_ action: ThreadActionKind) -> String {
        switch action {
        case .read: "Mark as read"
        case .done: "Mark as done"
        case .markAllRead: "Mark all as read"
        }
    }

    private static func describe(_ kind: FailureKind) -> String {
        switch kind {
        case .network: "Network error"
        case .httpStatus(let status): "HTTP \(status)"
        case .redirect: "Redirect refused"
        case .bodyTooLarge: "Response too large"
        case .malformedBody: "Malformed response"
        case .noToken: "No token"
        case .rateLimited: "Rate limited"
        case .unauthorized: "Unauthorized (401)"
        case .rejectedURL: "URL refused"
        }
    }
}
