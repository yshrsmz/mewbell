import Foundation
import Testing

@testable import Mewbell

struct CredentialStoreTests {
    private let alice = AccountID(host: "github.com", user: "alice")
    private let bob = AccountID(host: "github.com", user: "bob")
    private let token = AccessToken(ghOutput: Data("test-token".utf8))

    @Test func discardsOnlyTheAccountsThatAreGone() async throws {
        let store = CredentialStore()
        let token = try #require(token)
        await store.set(token, for: alice)
        await store.set(token, for: bob)
        await store.retainOnly([alice])
        #expect(await store.token(for: alice) != nil)
        #expect(await store.token(for: bob) == nil)
    }

    @Test func ignoresNewTokensAfterClosing() async throws {
        let store = CredentialStore()
        let token = try #require(token)
        await store.set(token, for: alice)
        await store.close()
        await store.set(token, for: bob)
        #expect(await store.token(for: alice) == nil)
        #expect(await store.token(for: bob) == nil)
    }

    @Test func removesOneAccount() async throws {
        let store = CredentialStore()
        let token = try #require(token)
        await store.set(token, for: alice)
        await store.set(token, for: bob)
        await store.remove(alice)
        #expect(await store.token(for: alice) == nil)
        #expect(await store.token(for: bob) != nil)
        await store.close()
        await store.remove(bob)
        #expect(await store.token(for: bob) == nil)
    }

    @Test func removesEverything() async throws {
        let store = CredentialStore()
        await store.set(try #require(token), for: alice)
        await store.removeAll()
        #expect(await store.token(for: alice) == nil)
    }
}
