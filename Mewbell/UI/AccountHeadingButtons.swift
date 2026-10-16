import SwiftUI

/// アカウントの通知をすべて既読にするボタン。1 回目で確認の表示に変わり、5 秒以内にもう一度押したときだけ実行する。
/// 確認の状態は見出しが持つ（すべて Done と同時に確認の表示にしないため）。
struct MarkAllReadButton: View {
    @Binding var confirming: Bool
    /// ボタンの文と件数（一覧に出ていない未読も既読にすることになるときは、件数を出さない）
    let labels: MarkAllReadLabels
    /// 一覧の最新のスレッドの `updated_at`。確認の途中で変わったら確認からやり直す
    let newest: Date?
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        ConfirmingButton(
            confirming: $confirming, icon: ActionIcon("envelope.open"), confirmation: labels.confirmation,
            help: labels.help(confirming: confirming),
            accessibilityLabel: labels.accessibilityLabel(confirming: confirming), isEnabled: isEnabled,
            target: Target(count: labels.count, newest: newest), action: action)
    }

    /// 確認の途中で変わったら確認からやり直す値。すべて既読は時刻で区切るので、件数と最新のスレッドで足りる
    private struct Target: Equatable {
        let count: Int
        let newest: Date?
    }
}

/// すべて既読のボタンの文。一覧に出ていない未読も既読になるとき（参加しているスレッドだけ、10 ページで打ち切った）は
/// 件数を出さず、そのことをツールチップと読み上げで伝える。
struct MarkAllReadLabels: Equatable {
    let count: Int
    let participatingOnly: Bool
    let isTruncated: Bool

    private static let notParticipating =
        "Also marks threads you are not participating in as read, up to the newest one shown here."
    private static let olderThanShown =
        "Also marks older unread threads that are not shown here as read (only the newest \(GitHubAPIClient.threadLimit) are fetched)."

    /// 操作の名前（VoiceOver の操作と、確認の前のツールチップ・読み上げ）
    static let read = "Mark all as read"

    /// 一覧に出ていない未読も既読にすることになるか
    var includesUnlisted: Bool { participatingOnly || isTruncated }

    var confirmation: String {
        includesUnlisted ? "Mark all as read?" : "Mark \(count) as read?"
    }

    func help(confirming: Bool) -> String {
        withNotes(confirming ? "Click again to mark all as read" : Self.read)
    }

    func accessibilityLabel(confirming: Bool) -> String {
        guard confirming else { return withNotes(Self.read) }
        return withNotes(includesUnlisted ? "Confirm marking all as read" : "Confirm marking \(count) as read")
    }

    private func withNotes(_ base: String) -> String {
        let notes = [participatingOnly ? Self.notParticipating : nil, isTruncated ? Self.olderThanShown : nil]
            .compactMap { $0 }
        return notes.isEmpty ? base : "\(base). \(notes.joined(separator: " "))"
    }
}

/// アカウントの一覧のスレッドをまとめて Done にするボタン。1 回目で確認の表示に変わり、5 秒以内にもう一度押したときだけ実行する。
/// 確認の状態は見出しが持つ（すべて既読と同時に確認の表示にしないため）。
struct MarkAllDoneButton: View {
    @Binding var confirming: Bool
    /// 一覧のスレッドの ID。Done はスレッドごとに効くので、件数や最新が同じでもスレッドが入れ替わったら確認からやり直す。
    /// 空のときは押せなくする
    let threadIDs: [String]
    let action: () -> Void

    var body: some View {
        let labels = MarkAllDoneLabels(count: threadIDs.count)
        ConfirmingButton(
            confirming: $confirming, icon: ActionIcon("checkmark"), confirmation: labels.confirmation,
            help: labels.help(confirming: confirming),
            accessibilityLabel: labels.accessibilityLabel(confirming: confirming), isEnabled: !threadIDs.isEmpty,
            target: threadIDs, action: action)
    }
}

/// すべて Done のボタンの文。対象は一覧に出ているスレッドだけなので、件数を出す。
struct MarkAllDoneLabels: Equatable {
    let count: Int

    /// 操作の名前（VoiceOver の操作と、確認の前のツールチップ・読み上げ）
    static let done = "Mark all as done"

    var confirmation: String { "Mark \(count) as done?" }

    func help(confirming: Bool) -> String {
        confirming ? "Click again to mark \(count) as done" : Self.done
    }

    func accessibilityLabel(confirming: Bool) -> String {
        confirming ? "Confirm marking \(count) as done" : Self.done
    }
}

#Preview("Account heading buttons") {
    let ids = ["1", "2", "3"]
    let three = MarkAllReadLabels(count: 3, participatingOnly: false, isTruncated: false)
    let none = MarkAllReadLabels(count: 0, participatingOnly: false, isTruncated: false)
    let participating = MarkAllReadLabels(count: 2, participatingOnly: true, isTruncated: false)
    let truncated = MarkAllReadLabels(count: 500, participatingOnly: false, isTruncated: true)
    VStack(alignment: .trailing, spacing: 12) {
        HStack(spacing: 2) {
            OpenWebNotificationsButton(host: "github.com") {}
            MarkAllReadButton(confirming: .constant(false), labels: three, newest: .now, isEnabled: true) {}
            MarkAllDoneButton(confirming: .constant(false), threadIDs: ids) {}
        }
        MarkAllReadButton(confirming: .constant(true), labels: three, newest: .now, isEnabled: true) {}
        MarkAllDoneButton(confirming: .constant(true), threadIDs: ids) {}
        HStack(spacing: 2) {
            MarkAllReadButton(confirming: .constant(false), labels: none, newest: nil, isEnabled: false) {}
            MarkAllDoneButton(confirming: .constant(false), threadIDs: []) {}
        }
        MarkAllReadButton(
            confirming: .constant(true), labels: participating, newest: .now, isEnabled: true
        ) {}
        MarkAllReadButton(
            confirming: .constant(false), labels: truncated, newest: .now, isEnabled: true
        ) {}
        MarkAllReadButton(
            confirming: .constant(true), labels: truncated, newest: .now, isEnabled: true
        ) {}
    }
    .padding()
}
