import Testing

@testable import Mewbell

struct GhCommandTests {
    @Test func buildsTheLoginCommandForTheHost() {
        #expect(GhCommand.login(host: "ghe.example.com") == "gh auth login --hostname ghe.example.com")
    }

    @Test func buildsTheSwitchCommandForTheUser() {
        #expect(
            GhCommand.switchUser(host: "github.com", user: "alice")
                == "gh auth switch --hostname github.com --user alice")
    }

    @Test func buildsTheRefreshCommandWithTheRepoScope() {
        #expect(
            GhCommand.refreshScopes(host: "ghe.example.com")
                == "gh auth refresh --hostname ghe.example.com --scopes repo")
    }
}
