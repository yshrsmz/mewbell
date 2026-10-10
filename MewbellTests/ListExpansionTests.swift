import Observation
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
        let state = ListExpansion().state(for: alice)
        #expect(!state.isCollapsed)
        #expect(!state.isCollapsed(app))
    }

    @Test func togglesAccountsAndRepositoriesSeparately() {
        let state = ListExpansion().state(for: alice)
        state.toggle()
        #expect(state.isCollapsed)
        #expect(!state.isCollapsed(app))
        state.toggle(app)
        #expect(state.isCollapsed(app))
        state.toggle()
        #expect(!state.isCollapsed)
        #expect(state.isCollapsed(app))
    }

    @Test func keepsTheSameRepositoryOfAnotherAccountApart() {
        let expansion = ListExpansion()
        expansion.state(for: alice).toggle(app)
        #expect(!expansion.state(for: bob).isCollapsed(app))
    }

    @Test func returnsTheSameStateForTheSameAccount() {
        let expansion = ListExpansion()
        #expect(expansion.state(for: alice) === expansion.state(for: alice))
        #expect(expansion.state(for: alice) !== expansion.state(for: bob))
    }

    @Test func expandsOnlyTheAccountAndTheRepositoriesWithNewThreads() {
        let expansion = ListExpansion()
        let aliceState = expansion.state(for: alice)
        let bobState = expansion.state(for: bob)
        aliceState.toggle(app)
        aliceState.toggle(lib)
        bobState.toggle(app)
        aliceState.toggle()
        bobState.toggle()

        expansion.expand(account: alice, repositories: [app])

        #expect(!aliceState.isCollapsed)
        #expect(!aliceState.isCollapsed(app))
        #expect(aliceState.isCollapsed(lib))
        #expect(bobState.isCollapsed)
        #expect(bobState.isCollapsed(app))
    }

    @Test func expandingAnAccountWithoutStateDoesNothing() {
        let expansion = ListExpansion()
        expansion.expand(account: alice, repositories: [app])
        let state = expansion.state(for: alice)
        #expect(!state.isCollapsed)
        #expect(!state.isCollapsed(app))
    }

    @Test func forgetsAccountsThatAreNoLongerShown() {
        let expansion = ListExpansion()
        let aliceState = expansion.state(for: alice)
        let bobState = expansion.state(for: bob)
        aliceState.toggle()
        aliceState.toggle(app)
        bobState.toggle()
        bobState.toggle(app)

        expansion.retain([alice])

        #expect(expansion.state(for: alice) === aliceState)
        #expect(aliceState.isCollapsed)
        #expect(aliceState.isCollapsed(app))
        let newBobState = expansion.state(for: bob)
        #expect(newBobState !== bobState)
        #expect(!newBobState.isCollapsed)
        #expect(!newBobState.isCollapsed(app))
    }

    /// 各区画は自分のアカウントの状態だけを読むので、ほかのアカウントの開閉では描き直されない。
    @Test func observesOnlyTheAccountThatChanged() {
        let expansion = ListExpansion()
        let aliceState = expansion.state(for: alice)
        let bobState = expansion.state(for: bob)
        let changes = ChangeFlag()
        withObservationTracking {
            _ = aliceState.isCollapsed
        } onChange: {
            MainActor.assumeIsolated { changes.changed = true }
        }

        bobState.toggle()
        #expect(!changes.changed)

        aliceState.toggle()
        #expect(changes.changed)
    }
}

@MainActor
private final class ChangeFlag {
    var changed = false
}
