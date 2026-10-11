import Foundation
import Testing

@testable import Mewbell

struct GhConfigDirectoryTests {
    private let home = URL(filePath: "/Users/me", directoryHint: .isDirectory)

    @Test func prefersGhConfigDir() {
        let environment = ["GH_CONFIG_DIR": "/custom/gh", "XDG_CONFIG_HOME": "/xdg"]
        let resolved = GhConfigDirectory.resolve(environment: environment, homeDirectory: home)
        #expect(resolved.url.path == "/custom/gh")
        #expect(resolved.source == .ghConfigDir)
    }

    @Test func usesXdgConfigHome() {
        let environment = ["GH_CONFIG_DIR": "", "XDG_CONFIG_HOME": "/xdg"]
        // 空の `GH_CONFIG_DIR` は使わない
        let resolved = GhConfigDirectory.resolve(environment: environment, homeDirectory: home)
        #expect(resolved.url.path == "/xdg/gh")
        #expect(resolved.source == .xdgConfigHome)
    }

    @Test func defaultsToDotConfig() {
        let resolved = GhConfigDirectory.resolve(environment: [:], homeDirectory: home)
        #expect(resolved.url.path == "/Users/me/.config/gh")
        #expect(resolved.source == .defaultLocation)
    }
}

struct ConfigDirectoryValidatorTests {
    private let directory: TemporaryDirectory

    init() throws {
        directory = try TemporaryDirectory()
    }

    @Test func acceptsAnOwnedDirectory() throws {
        let path = directory.url.appending(path: "gh").path
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
        #expect(ConfigDirectoryValidator.validate(path) != nil)
    }

    @Test func rejectsRelativeMissingAndFilePaths() throws {
        let file = try directory.makeFile("hosts.yml", permissions: 0o600)
        #expect(ConfigDirectoryValidator.validate("gh") == nil)
        #expect(ConfigDirectoryValidator.validate(directory.url.appending(path: "missing").path) == nil)
        #expect(ConfigDirectoryValidator.validate(file) == nil)
    }

    @Test func rejectsAWorldWritableDirectory() throws {
        let path = directory.url.appending(path: "shared").path
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: path)
        #expect(ConfigDirectoryValidator.validate(path) == nil)
    }

    @Test func checksTheTargetOfASymbolicLink() throws {
        let target = directory.url.appending(path: "shared").path
        try FileManager.default.createDirectory(atPath: target, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: target)
        let link = directory.url.appending(path: "link").path
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)
        #expect(ConfigDirectoryValidator.validate(link) == nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target)
        #expect(ConfigDirectoryValidator.validate(link) != nil)
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

    @Test(arguments: ["alice", "dependabot[bot]", "github-actions[bot]", "Copilot"])
    func acceptsValidActors(_ login: String) {
        #expect(GhIdentifier.isValidActor(login))
    }

    @Test(arguments: ["", "-x", "[bot]", "a[bot]x", "a[bot][bot]", "-x[bot]", "a b[bot]"])
    func rejectsInvalidActors(_ login: String) {
        #expect(!GhIdentifier.isValidActor(login))
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

    @Test func loadRejectsAFifoWithoutBlocking() throws {
        let directory = try TemporaryDirectory()
        let path = directory.url.appending(path: "hosts.yml").path
        #expect(mkfifo(path, 0o600) == 0)
        #expect(throws: HostsFile.LoadError.unreadable) { try HostsFile.load(from: URL(filePath: path)) }
    }

    @Test func loadRejectsAHugeFile() throws {
        let directory = try TemporaryDirectory()
        let path = try directory.makeFile("hosts.yml", contents: String(repeating: "#", count: HostsFile.sizeLimit + 1))
        #expect(throws: HostsFile.LoadError.tooLarge) { try HostsFile.load(from: URL(filePath: path)) }
    }
}
