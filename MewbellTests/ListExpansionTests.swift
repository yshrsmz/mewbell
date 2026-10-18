import Foundation
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
            kind: .issue, subjectURL: nil, repository: repository, detailsSubject: nil)
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
}
