import Testing

@testable import Mewbell

struct GhCommandTests {
    @Test func buildsTheReloginCommandForTheHost() {
        #expect(
            GhCommand.relogin(for: AccountID(host: "ghe.example.com", user: "alice"))
                == "gh auth login --hostname ghe.example.com")
    }

    @Test func buildsTheSwitchCommandForTheUser() {
        #expect(
            GhCommand.switchUser(to: AccountID(host: "github.com", user: "alice"))
                == "gh auth switch --hostname github.com --user alice")
    }

    @Test func buildsTheRefreshCommandWithTheRepoScope() {
        #expect(
            GhCommand.refreshScopes(for: AccountID(host: "ghe.example.com", user: "alice"))
                == "gh auth refresh --hostname ghe.example.com --scopes repo")
    }
}
