import Foundation
import Testing

@testable import Mewbell

struct ActionFailureMessageTests {
    private let alice = Account(id: AccountID(host: "github.com", user: "alice"), isActive: true)
    private let bob = Account(id: AccountID(host: "acme.ghe.com", user: "bob"), isActive: true)

    private func failure(_ action: ThreadActionKind, _ kind: FailureKind) -> ActionFailure {
        ActionFailure(action: action, kind: kind, occurredAt: Date(timeIntervalSince1970: 0))
    }

    @Test func describesAFailedDoneWithoutTheStatusCode() {
        let failure = failure(.done, .httpStatus(500))
        let text = ActionFailureMessage.text(for: failure)
        #expect(text == "Could not mark a thread as done. Unread threads come back after the next fetch.")
        #expect(!text.contains("500"))
        #expect(ActionFailureMessage.command(for: failure, account: alice) == nil)
    }

    @Test func asksToLogInAgainAfterAnUnauthorizedRead() {
        let failure = failure(.read, .unauthorized)
        #expect(
            ActionFailureMessage.text(for: failure).hasPrefix("Could not mark a thread as read because GitHub rejected")
        )
        #expect(ActionFailureMessage.command(for: failure, account: alice) == "gh auth login --hostname github.com")
    }

    @Test func mentionsTheRateLimit() {
        let failure = failure(.markAllRead, .rateLimited)
        #expect(
            ActionFailureMessage.text(for: failure).hasPrefix("Could not mark all as read because of the rate limit."))
        #expect(ActionFailureMessage.command(for: failure, account: bob) == nil)
    }

    @Test func givesNoReasonForOtherFailures() {
        let failure = failure(.read, .network)
        #expect(
            ActionFailureMessage.text(for: failure)
                == "Could not mark a thread as read. Unread threads come back after the next fetch.")
        #expect(ActionFailureMessage.command(for: failure, account: alice) == nil)
    }

    @Test func doesNotPromiseThreadsBackWhenMarkAllReadWasNotSent() {
        let text = ActionFailureMessage.text(for: failure(.markAllRead, .noToken))
        #expect(text == "Could not mark all as read.")
    }
}
