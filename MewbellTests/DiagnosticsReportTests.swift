import Foundation
import Testing

@testable import Mewbell

struct DiagnosticsReportTests {
    private let alice = Account(id: AccountID(host: "github.com", user: "alice"), isActive: true)
    private let bob = Account(id: AccountID(host: "github.com", user: "bob"), isActive: false)
    private let erin = Account(id: AccountID(host: "ghe.example.com", user: "erin"), isActive: true)
    /// 2026-10-10T03:00:00Z
    private let noon = Date(timeIntervalSince1970: 1_791_601_200)

    private let detection = GhDiagnostics(
        executable: GhLocation(url: URL(filePath: "/opt/homebrew/Cellar/gh/2.62.0/bin/gh"), source: .standardLocation),
        version: GhVersion(major: 2, minor: 62, patch: 0),
        configDirectory: GhConfigDirectory.Resolved(
            url: URL(filePath: "/Users/me/.config/gh", directoryHint: .isDirectory), source: .defaultLocation))

    private func thread(_ id: String) throws -> NotificationThread {
        NotificationThread(
            id: id, reason: "mention", updatedAt: noon, title: "Secret plan for ghp_ABCDEF \(id)", kind: .issue,
            subjectURL: URL(string: "https://api.github.com/repos/octo/app/issues/\(id)"),
            repository: try #require(RepositoryName(fullName: "octo/app")), subjectNumber: nil)
    }

    private func report(
        ghDetection: GhDiagnostics? = nil, statuses: [AccountStatus], feeds: [AccountID: FeedState],
        preferences: [AccountID: AccountPreferences] = [:]
    ) -> DiagnosticsReport {
        let state = DiscoveryState.accounts(statuses)
        return DiagnosticsReport(
            ghDetection: ghDetection ?? detection, state: state,
            accounts: DiagnosticsReport.accounts(in: state, feeds: feeds) { preferences[$0] ?? .default },
            appVersion: "0.1.0 (1)", osVersion: "Version 26.0 (Build 25A100)")
    }

    private func rows(_ report: DiagnosticsReport, _ title: String) -> [String: DiagnosticsReport.Row] {
        let section = report.sections.first { $0.title == title }
        return Dictionary(uniqueKeysWithValues: (section?.rows ?? []).map { ($0.label, $0) })
    }

    private func loadedAlice() throws -> FeedState {
        var feed = FeedState(
            phase: .loaded(updatedAt: noon), threads: [try thread("1"), try thread("2"), try thread("3")])
        feed.diagnostics = FeedDiagnostics(
            lastFetchedAt: noon, nextFetchAt: noon.addingTimeInterval(60),
            pollInterval: PollIntervalInfo(seconds: 60, fromHeader: true),
            scopes: OAuthScopes(header: "repo, read:org"))
        return feed
    }

    @Test func describesTheGh() {
        let rows = rows(report(statuses: [], feeds: [:]), "gh")
        #expect(rows["Status"]?.text == "0 accounts")
        #expect(rows["Executable"]?.text == "/opt/homebrew/Cellar/gh/2.62.0/bin/gh")
        #expect(rows["Found via"]?.text == "Standard location")
        #expect(rows["Version"]?.text == "2.62.0 (supported)")
        #expect(rows["Config directory"]?.text == "/Users/me/.config/gh")
        #expect(rows["Config directory from"]?.text == "Default")
    }

    @Test func showsUnknownValuesWhenGhIsMissing() {
        let report = DiagnosticsReport(
            ghDetection: GhDiagnostics(), state: .ghNotFound, accounts: [], appVersion: "0.1.0", osVersion: "26.0")
        let rows = rows(report, "gh")
        #expect(rows["Status"]?.text == "gh not found")
        #expect(rows["Executable"]?.text == nil)
        #expect(rows["Version"]?.text == nil)
        #expect(report.plainText.contains("Version: Unknown"))
        #expect(report.sections.map(\.title) == ["Mewbell", "gh"])
    }

    @Test func describesALoadedAccount() throws {
        let rows = rows(
            report(statuses: [AccountStatus(account: alice, tokenState: .ready)], feeds: [alice.id: try loadedAlice()]),
            "github.com/alice")
        #expect(rows["Host kind"]?.text == "GitHub.com")
        #expect(rows["Active in gh"]?.text == "Yes")
        #expect(rows["Token"]?.text == "Ready")
        #expect(rows["Participating only"]?.text == "Off")
        #expect(rows["macOS notifications"]?.text == "On")
        #expect(rows["Fetch"]?.text == "Loaded")
        #expect(rows["Last fetched"]?.time == noon)
        #expect(rows["Next fetch"]?.time == noon.addingTimeInterval(60))
        #expect(rows["Poll interval"]?.text == "60 s (X-Poll-Interval)")
        #expect(rows["Scopes"]?.text == "read:org, repo")
        #expect(rows["Unread"]?.text == "3")
        #expect(rows["Last fetch failure"]?.text == "None")
        #expect(rows["Last action failure"]?.text == "None")
    }

    @Test func showsADisabledAccountAsNotPolling() {
        let report = report(
            statuses: [AccountStatus(account: bob, tokenState: .disabled)], feeds: [:],
            preferences: [bob.id: AccountPreferences(isEnabled: false)])
        let rows = rows(report, "github.com/bob")
        #expect(rows["Token"]?.text == "Disabled")
        #expect(rows["Fetch"]?.text == "Not polling")
        #expect(rows["Next fetch"] == nil)
    }

    @Test func showsTheTruncationAndTheLastFailures() throws {
        var feed = try loadedAlice()
        feed.isTruncated = true
        feed.diagnostics.lastFetchFailure = TimedFailure(kind: .httpStatus(502), occurredAt: noon)
        feed.diagnostics.lastActionFailure = ActionFailure(action: .done, kind: .httpStatus(500), occurredAt: noon)
        let report = report(statuses: [AccountStatus(account: alice, tokenState: .ready)], feeds: [alice.id: feed])
        let rows = rows(report, "github.com/alice")
        #expect(rows["Unread"]?.text == "3 (stopped at 10 pages)")
        #expect(rows["Last fetch failure"]?.text == "HTTP 502")
        #expect(rows["Last action failure"]?.text == "Mark as done: HTTP 500")
        #expect(rows["Last action failure"]?.time == noon)
        #expect(report.plainText.contains("Last action failure: Mark as done: HTTP 500 (2026-10-10T03:00:00Z)"))
    }

    @Test func redactsTokenLikeStringsInTheCopiedText() {
        var detection = detection
        detection.configDirectory = GhConfigDirectory.Resolved(
            url: URL(filePath: "/Users/me/ghp_abcdefghijklmnop/gh", directoryHint: .isDirectory), source: .override)
        let text = report(ghDetection: detection, statuses: [], feeds: [:]).plainText
        #expect(!text.contains("ghp_abcdefghijklmnop"))
        #expect(text.contains("/Users/me/<redacted>/gh"))
        #expect(text.contains("Config directory from: Settings override"))
    }

    @Test func leavesOutTitlesAndURLs() throws {
        var stopped = FeedState(phase: .unauthorized, threads: [])
        stopped.diagnostics.lastFetchFailure = TimedFailure(kind: .unauthorized, occurredAt: noon)
        let report = report(
            statuses: [
                AccountStatus(account: alice, tokenState: .ready), AccountStatus(account: erin, tokenState: .ready),
            ],
            feeds: [alice.id: try loadedAlice(), erin.id: stopped])
        let shown = report.sections.flatMap(\.rows).compactMap(\.text).joined(separator: "\n")
        for text in [shown, report.plainText] {
            #expect(!text.contains("Secret plan"))
            #expect(!text.contains("https://"))
            #expect(!text.contains("api.github.com"))
            #expect(!text.contains("/api/v3"))
        }
        #expect(rows(report, "ghe.example.com/erin")["Fetch"]?.text == "Stopped: unauthorized")
    }
}
