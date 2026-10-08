import Foundation
import Testing

@testable import Mewbell

struct GhConfigDirectoryTests {
    private let home = URL(filePath: "/Users/me", directoryHint: .isDirectory)

    @Test func prefersGhConfigDir() {
        let environment = ["GH_CONFIG_DIR": "/custom/gh", "XDG_CONFIG_HOME": "/xdg"]
        #expect(GhConfigDirectory.resolve(environment: environment, homeDirectory: home).path == "/custom/gh")
    }

    @Test func usesXdgConfigHome() {
        let environment = ["GH_CONFIG_DIR": "", "XDG_CONFIG_HOME": "/xdg"]
        #expect(GhConfigDirectory.resolve(environment: environment, homeDirectory: home).path == "/xdg/gh")
    }

    @Test func defaultsToDotConfig() {
        #expect(GhConfigDirectory.resolve(environment: [:], homeDirectory: home).path == "/Users/me/.config/gh")
    }
}

struct GhIdentifierTests {
    @Test(arguments: ["github.com", "acme.ghe.com", "GitHub.Example.com", "ghe-1.internal", "localhost"])
    func acceptsValidHosts(_ host: String) {
        #expect(GhIdentifier.isValidHost(host))
    }

    @Test(arguments: [
        "", "-x", "--help", "evil host/path", "a..b", ".github.com", "github.com.", "-a.com", "a-.com",
        "host:8443", "ex@mple.com", "exämple.com", String(repeating: "a", count: 64) + ".com",
    ])
    func rejectsInvalidHosts(_ host: String) {
        #expect(!GhIdentifier.isValidHost(host))
    }

    @Test(arguments: ["alice", "alice_acme", "a", "Alice-B", "1234"])
    func acceptsValidUsers(_ user: String) {
        #expect(GhIdentifier.isValidUser(user))
    }

    @Test(arguments: [
        "", "-x", "--help", "alice bob", "alice/bob", "alice.bob", "ålice", String(repeating: "a", count: 101),
    ])
    func rejectsInvalidUsers(_ user: String) {
        #expect(!GhIdentifier.isValidUser(user))
    }
}

struct HostsFileTests {
    @Test func readsTheMultiAccountFormat() throws {
        let yaml = """
            github.com:
                git_protocol: https
                users:
                    alice:
                    bob:
                user: alice
            """
        let hosts = try HostsFile.parse(yaml)
        #expect(hosts == HostsFile(hosts: [.init(name: "github.com", users: ["alice", "bob"], activeUser: "alice")]))
    }

    @Test func readsTheLegacyFormatWithoutKeepingTheToken() throws {
        let yaml = """
            ghe.example.com:
                oauth_token: test-token
                user: carol
                git_protocol: ssh
            """
        let hosts = try HostsFile.parse(yaml)
        #expect(hosts == HostsFile(hosts: [.init(name: "ghe.example.com", users: ["carol"], activeUser: "carol")]))
        #expect(!String(reflecting: hosts).contains("test-token"))
    }

    @Test func ignoresTokensStoredUnderUsers() throws {
        let yaml = """
            github.com:
                users:
                    alice:
                        oauth_token: test-token
                user: alice
                oauth_token: test-token
            """
        let hosts = try HostsFile.parse(yaml)
        #expect(hosts.hosts.first?.users == ["alice"])
        #expect(!String(reflecting: hosts).contains("test-token"))
    }

    @Test func skipsInvalidEntriesAndKeepsTheRest() throws {
        let yaml = """
            github.com:
                users:
                    --help:
                    alice:
                    alice_acme:
                user: --help
            evil host/path:
                user: mallory
            -flag.example.com:
                user: mallory
            Ghe.Example.com:
                users:
                    dave:
            empty.example.com:
                git_protocol: https
            """
        let hosts = try HostsFile.parse(yaml)
        #expect(
            hosts
                == HostsFile(hosts: [
                    .init(name: "github.com", users: ["alice", "alice_acme"], activeUser: nil),
                    .init(name: "ghe.example.com", users: ["dave"], activeUser: nil),
                ]))
    }

    @Test func fallsBackToUserWhenUsersIsEmpty() throws {
        let hosts = try HostsFile.parse("github.com:\n    users: {}\n    user: alice\n")
        #expect(hosts == HostsFile(hosts: [.init(name: "github.com", users: ["alice"], activeUser: "alice")]))
    }

    @Test func mergesUsersThatDifferOnlyInCase() throws {
        let yaml = """
            github.com:
                users:
                    Alice:
                    alice:
                user: alice
            """
        let hosts = try HostsFile.parse(yaml)
        #expect(hosts == HostsFile(hosts: [.init(name: "github.com", users: ["Alice"], activeUser: "Alice")]))
    }

    @Test func treatsAnEmptyFileAsNoHosts() throws {
        #expect(try HostsFile.parse("") == HostsFile(hosts: []))
    }

    @Test(arguments: ["github.com: [unclosed", "- a\n- b\n", "just text"])
    func rejectsMalformedYaml(_ yaml: String) {
        #expect(throws: HostsFile.LoadError.malformed) { try HostsFile.parse(yaml) }
    }

    @Test func loadReturnsNilWhenTheFileIsMissing() throws {
        let directory = try TemporaryDirectory()
        #expect(try HostsFile.load(from: directory.url.appending(path: "hosts.yml")) == nil)
    }

    @Test func loadReadsAFile() throws {
        let directory = try TemporaryDirectory()
        let path = try directory.makeFile("hosts.yml", contents: "github.com:\n    user: alice\n", permissions: 0o600)
        #expect(try HostsFile.load(from: URL(filePath: path))?.hosts.first?.users == ["alice"])
    }

    @Test func loadRejectsAnUnreadableFile() throws {
        let directory = try TemporaryDirectory()
        let path = try directory.makeFile("hosts.yml", contents: "github.com:\n    user: alice\n", permissions: 0o000)
        #expect(throws: HostsFile.LoadError.unreadable) { try HostsFile.load(from: URL(filePath: path)) }
    }

    @Test func loadRejectsAHugeFile() throws {
        let directory = try TemporaryDirectory()
        let path = try directory.makeFile("hosts.yml", contents: String(repeating: "#", count: HostsFile.sizeLimit + 1))
        #expect(throws: HostsFile.LoadError.tooLarge) { try HostsFile.load(from: URL(filePath: path)) }
    }
}
