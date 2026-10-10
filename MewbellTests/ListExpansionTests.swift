import Testing

@testable import Mewbell

@MainActor
struct ListExpansionTests {
    private let alice = AccountID(host: "github.com", user: "alice")
    private let bob = AccountID(host: "github.com", user: "bob")
    private let app: RepositoryName
    private let lib: RepositoryName

    init() throws {
        app = try #require(RepositoryName(fullName: "octo/app"))
        lib = try #require(RepositoryName(fullName: "octo/lib"))
    }

    @Test func startsWithEverythingExpanded() {
        let expansion = ListExpansion()
        #expect(!expansion.isCollapsed(alice))
        #expect(!expansion.isCollapsed(RepositoryKey(account: alice, repository: app)))
    }

    @Test func togglesAccountsAndRepositoriesSeparately() {
        let expansion = ListExpansion()
        let aliceApp = RepositoryKey(account: alice, repository: app)
        expansion.toggle(alice)
        #expect(expansion.isCollapsed(alice))
        #expect(!expansion.isCollapsed(aliceApp))
        expansion.toggle(aliceApp)
        #expect(expansion.isCollapsed(aliceApp))
        expansion.toggle(alice)
        #expect(!expansion.isCollapsed(alice))
        #expect(expansion.isCollapsed(aliceApp))
    }

    @Test func keepsTheSameRepositoryOfAnotherAccountApart() {
        let expansion = ListExpansion()
        expansion.toggle(RepositoryKey(account: alice, repository: app))
        #expect(!expansion.isCollapsed(RepositoryKey(account: bob, repository: app)))
    }

    @Test func expandsOnlyTheAccountAndTheRepositoriesWithNewThreads() {
        let expansion = ListExpansion()
        let aliceApp = RepositoryKey(account: alice, repository: app)
        let aliceLib = RepositoryKey(account: alice, repository: lib)
        let bobApp = RepositoryKey(account: bob, repository: app)
        for key in [aliceApp, aliceLib, bobApp] {
            expansion.toggle(key)
        }
        expansion.toggle(alice)
        expansion.toggle(bob)

        expansion.expand(account: alice, repositories: [app])

        #expect(!expansion.isCollapsed(alice))
        #expect(!expansion.isCollapsed(aliceApp))
        #expect(expansion.isCollapsed(aliceLib))
        #expect(expansion.isCollapsed(bob))
        #expect(expansion.isCollapsed(bobApp))
    }

    @Test func forgetsAccountsThatAreNoLongerShown() {
        let expansion = ListExpansion()
        let aliceApp = RepositoryKey(account: alice, repository: app)
        let bobApp = RepositoryKey(account: bob, repository: app)
        expansion.toggle(alice)
        expansion.toggle(bob)
        expansion.toggle(aliceApp)
        expansion.toggle(bobApp)

        expansion.retain([alice])

        #expect(expansion.isCollapsed(alice))
        #expect(expansion.isCollapsed(aliceApp))
        #expect(!expansion.isCollapsed(bob))
        #expect(!expansion.isCollapsed(bobApp))
    }
}
