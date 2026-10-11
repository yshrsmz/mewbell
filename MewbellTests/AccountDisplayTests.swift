import Testing

@testable import Mewbell

struct AccountDisplayTests {
    @Test func labelsTheHostWithItsKind() {
        let account = Account(id: AccountID(host: "acme.ghe.com", user: "dave"), isActive: false)
        #expect(account.hostLabel == "acme.ghe.com — GHE Cloud")
    }

    @Test func namesTheAccountWithItsHost() {
        let account = AccountID(host: "github.com", user: "alice")
        #expect(account.displayName == "alice (github.com)")
    }
}
