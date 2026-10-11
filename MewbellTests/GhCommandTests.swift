import Testing

@testable import Mewbell

struct GhCommandTests {
    @Test func buildsTheLoginCommandWithoutAHost() {
        #expect(GhCommand.login() == "gh auth login")
    }

    @Test func buildsTheLoginCommandForTheHost() {
        #expect(GhCommand.login(host: "ghe.example.com") == "gh auth login --hostname ghe.example.com")
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

    @Test func buildsTheHomebrewCommands() {
        #expect(GhCommand.install == "brew install gh")
        #expect(GhCommand.upgrade == "brew upgrade gh")
    }
}
