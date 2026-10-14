import AppKit
import SwiftUI

/// Diagnostics タブ。gh の検出の結果とアカウントごとの状態を、今の値から組み立てて出す
/// （開いても gh の実行や通知の取得はしない）。トークン、API の URL、スレッドの件名は出さない。
struct DiagnosticsSettingsView: View {
    /// 報告を作る。ポーリングのたびに変わる通知の状態を読むので、値ではなくクロージャで受け取り、この View の body で呼ぶ
    /// （描き直すのをこのタブの中にとどめ、設定ウィンドウのルートとほかのタブを描き直さない）
    let report: () -> DiagnosticsReport

    var body: some View {
        DiagnosticsReportView(report: report())
    }
}

/// `DiagnosticsReport` の節と行を並べ、Copy でテキストをクリップボードに入れる。
struct DiagnosticsReportView: View {
    let report: DiagnosticsReport
    @State private var copied = false
    /// 押した回数（押し直したら「Copied」を戻す待ちをやり直す）
    @State private var copyCount = 0

    var body: some View {
        Form {
            ForEach(report.sections) { section in
                Section(section.title) {
                    ForEach(section.rows) { row in
                        LabeledContent(row.label) {
                            DiagnosticsValueText(row: row)
                        }
                    }
                }
            }
            Section {
                HStack {
                    Text("Copied text has tokens redacted and leaves out API URLs and thread titles.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc", action: copy)
                        .help("Copy the diagnostics as text")
                        .accessibilityLabel(copied ? "Copied the diagnostics" : "Copy the diagnostics as text")
                }
            }
        }
        .formStyle(.grouped)
        .task(id: copyCount) {
            guard copied, (try? await Task.sleep(for: .seconds(2))) != nil else { return }
            copied = false
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.plainText, forType: .string)
        copied = true
        copyCount += 1
    }
}

/// 行の値。時刻があれば、時刻と相対時刻（毎秒進める）を添える。
private struct DiagnosticsValueText: View {
    let row: DiagnosticsReport.Row

    var body: some View {
        HStack(spacing: 4) {
            if let text = row.text {
                Text(text)
            } else if row.time == nil {
                Text(DiagnosticsReport.unknown).foregroundStyle(.secondary)
            }
            if let time = row.time {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    // 文字列にしてから渡す（時刻が進むと文字列が変わり、描き直される）
                    Text(
                        "\(time.formatted(date: .omitted, time: .standard)) · \(time.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))"
                    )
                    .foregroundStyle(.secondary)
                }
            }
        }
        .textSelection(.enabled)
        .multilineTextAlignment(.trailing)
    }
}

#Preview("Accounts") {
    let now = Date()
    let alice = Account(id: AccountID(host: "github.com", user: "alice"), isActive: true)
    let bob = Account(id: AccountID(host: "github.com", user: "bob"), isActive: false)
    let erin = Account(id: AccountID(host: "ghe.example.com", user: "erin"), isActive: true)
    var aliceFeed = FeedState(phase: .loaded(updatedAt: now.addingTimeInterval(-20)), threads: [], isTruncated: true)
    aliceFeed.diagnostics = FeedDiagnostics(
        lastFetchedAt: now.addingTimeInterval(-20), nextFetchAt: now.addingTimeInterval(40),
        pollInterval: PollIntervalInfo(seconds: 60, fromHeader: true), scopes: OAuthScopes(header: "repo, read:org"),
        lastActionFailure: ActionFailure(
            action: .done, kind: .httpStatus(500), occurredAt: now.addingTimeInterval(-300)))
    var erinFeed = FeedState(phase: .unauthorized, threads: [])
    erinFeed.diagnostics.lastFetchFailure = TimedFailure(kind: .unauthorized, occurredAt: now.addingTimeInterval(-600))
    let state = DiscoveryState.accounts([
        AccountStatus(account: alice, tokenState: .ready), AccountStatus(account: bob, tokenState: .disabled),
        AccountStatus(account: erin, tokenState: .ready),
    ])
    return DiagnosticsReportView(
        report: DiagnosticsReport(
            ghDetection: GhDiagnostics(
                executable: GhLocation(url: URL(filePath: "/opt/homebrew/bin/gh"), source: .standardLocation),
                version: GhVersion(major: 2, minor: 62, patch: 0),
                configDirectory: GhConfigDirectory.Resolved(
                    url: URL(filePath: "/Users/me/.config/gh"), source: .defaultLocation)),
            state: state,
            accounts: DiagnosticsReport.accounts(
                in: state, feeds: [alice.id: aliceFeed, erin.id: erinFeed]
            ) { $0 == bob.id ? AccountPreferences(isEnabled: false) : .default },
            appVersion: "0.1.0 (1)", osVersion: "Version 26.0")
    )
    .frame(width: 520, height: 420)
}

#Preview("gh not found") {
    DiagnosticsReportView(
        report: DiagnosticsReport(
            ghDetection: GhDiagnostics(), state: .ghNotFound, accounts: [], appVersion: "0.1.0 (1)",
            osVersion: "Version 26.0")
    )
    .frame(width: 520, height: 420)
}
