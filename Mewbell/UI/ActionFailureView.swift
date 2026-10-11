import SwiftUI

/// ポップオーバーに出す、操作の失敗の文。状態コードや API の文は入れない。
enum ActionFailureMessage {
    static func text(for failure: ActionFailure) -> String {
        let action =
            switch failure.action {
            case .read: "Could not mark a thread as read"
            case .done: "Could not mark a thread as done"
            case .markAllRead: "Could not mark all as read"
            }
        let reason =
            switch failure.kind {
            case .unauthorized: " because GitHub rejected the token from gh"
            case .rateLimited: " because of the rate limit"
            default: ""
            }
        // トークンが無くてすべて既読を送らなかったときは、一覧から何も外していない
        let comesBack =
            failure.action == .markAllRead && failure.kind == .noToken
            ? nil : "Unread threads come back after the next fetch."
        let followUp = [failure.kind == .unauthorized ? "Log in again with the command below." : nil, comesBack]
            .compactMap { $0 }
        return (["\(action)\(reason)."] + followUp).joined(separator: " ")
    }

    /// 文に添えるコマンド（認証エラーのときだけ）。
    static func command(for failure: ActionFailure, account: Account) -> String? {
        failure.kind == .unauthorized ? GhCommand.relogin(for: account.id) : nil
    }
}

/// アカウントの区画に出す、操作の失敗の知らせ（幅に合わせて折り返す）。次の取得が成功すると `FeedState.actionFailure` ごと消える。
struct ActionFailureView: View {
    let failure: ActionFailure
    let account: Account

    var body: some View {
        VStack(alignment: .leading, spacing: ListLayout.noteSpacing) {
            Label {
                Text(ActionFailureMessage.text(for: failure))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            }
            if let command = ActionFailureMessage.command(for: failure, account: account) {
                CommandRow(command: command)
            }
        }
        .sectionNote()
    }
}

#Preview {
    let alice = Account(id: AccountID(host: "github.com", user: "alice"), isActive: true)
    VStack(alignment: .leading, spacing: 12) {
        ActionFailureView(
            failure: ActionFailure(action: .done, kind: .httpStatus(500), occurredAt: .now), account: alice)
        ActionFailureView(
            failure: ActionFailure(action: .read, kind: .unauthorized, occurredAt: .now), account: alice)
        ActionFailureView(
            failure: ActionFailure(action: .markAllRead, kind: .rateLimited, occurredAt: .now),
            account: Account(id: AccountID(host: "acme.ghe.com", user: "bob"), isActive: true))
    }
    .padding()
    .frame(width: 380)
}
