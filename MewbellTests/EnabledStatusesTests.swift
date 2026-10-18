import Testing

@testable import Mewbell

struct EnabledStatusesTests {
    private func status(_ user: String, _ tokenState: TokenState) -> AccountStatus {
        AccountStatus(
            account: Account(id: AccountID(host: "github.com", user: user), isActive: false), tokenState: tokenState)
    }

    @Test func keepsAccountsOtherThanDisabledInOrder() {
        let state = DiscoveryState.accounts([
            status("alice", .ready), status("bob", .disabled), status("carol", .unavailable),
            status("dave", .fetching), status("erin", .disabled),
        ])
        #expect(state.enabledStatuses.map(\.account.user) == ["alice", "carol", "dave"])
        #expect(state.retainedAccountIDs?.map(\.user).sorted() == ["alice", "carol", "dave"])
    }

    @Test func defersRetainingWhileChecking() {
        #expect(DiscoveryState.checking.enabledStatuses.isEmpty)
        #expect(DiscoveryState.checking.retainedAccountIDs == nil)
    }

    @Test func keepsNothingWithoutAccounts() {
        #expect(DiscoveryState.notLoggedIn.enabledStatuses.isEmpty)
        #expect(DiscoveryState.notLoggedIn.retainedAccountIDs == [])
    }
}
