import Foundation
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

    private func thread(_ id: String, in repository: RepositoryName) -> NotificationThread {
        NotificationThread(
            id: id, reason: "subscribed", updatedAt: Date(timeIntervalSince1970: 0), title: "Thread \(id)",
            kind: .issue, subjectURL: nil, repository: repository, subjectNumber: nil)
    }

    @Test func startsWithEverythingExpanded() {
        let state = ListExpansion().state(for: alice)
        #expect(!state.isCollapsed)
        #expect(!state.isRepositoryCollapsed(app))
    }

    @Test func togglesAccountsAndRepositoriesSeparately() {
        let state = ListExpansion().state(for: alice)
        state.toggle()
        #expect(state.isCollapsed)
        #expect(!state.isRepositoryCollapsed(app))
        state.toggleRepository(app)
        #expect(state.isRepositoryCollapsed(app))
        state.toggle()
        #expect(!state.isCollapsed)
        #expect(state.isRepositoryCollapsed(app))
    }

    @Test func keepsTheSameRepositoryOfAnotherAccountApart() {
        let expansion = ListExpansion()
        expansion.state(for: alice).toggleRepository(app)
        #expect(!expansion.state(for: bob).isRepositoryCollapsed(app))
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
        aliceState.toggleRepository(app)
        aliceState.toggleRepository(lib)
        bobState.toggleRepository(app)
        aliceState.toggle()
        bobState.toggle()

        expansion.expand(account: alice, newThreads: [thread("1", in: app), thread("2", in: app)])

        #expect(!aliceState.isCollapsed)
        #expect(!aliceState.isRepositoryCollapsed(app))
        #expect(aliceState.isRepositoryCollapsed(lib))
        #expect(bobState.isCollapsed)
        #expect(bobState.isRepositoryCollapsed(app))
    }

    @Test func expandingAnAccountWithoutStateDoesNothing() {
        let expansion = ListExpansion()
        expansion.expand(account: alice, newThreads: [thread("1", in: app)])
        let state = expansion.state(for: alice)
        #expect(!state.isCollapsed)
        #expect(!state.isRepositoryCollapsed(app))
    }

    @Test func forgetsAccountsThatAreNoLongerShown() {
        let expansion = ListExpansion()
        let aliceState = expansion.state(for: alice)
        let bobState = expansion.state(for: bob)
        aliceState.toggle()
        aliceState.toggleRepository(app)
        bobState.toggle()
        bobState.toggleRepository(app)

        expansion.retain([alice])

        #expect(expansion.state(for: alice) === aliceState)
        #expect(aliceState.isCollapsed)
        #expect(aliceState.isRepositoryCollapsed(app))
        let newBobState = expansion.state(for: bob)
        #expect(newBobState !== bobState)
        #expect(!newBobState.isCollapsed)
        #expect(!newBobState.isRepositoryCollapsed(app))
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
