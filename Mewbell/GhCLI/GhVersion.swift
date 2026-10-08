import Foundation

/// gh のバージョン（`gh --version` の 1 行目の `gh version X.Y.Z`）。
struct GhVersion: Sendable, Comparable, CustomStringConvertible {
    /// `gh auth token --user` が入ったバージョン
    static let minimumSupported = GhVersion(major: 2, minor: 40, patch: 0)

    let major: Int
    let minor: Int
    let patch: Int

    init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    init?(versionOutput: String) {
        guard let firstLine = versionOutput.split(whereSeparator: \.isNewline).first,
            let match = firstLine.prefixMatch(of: /gh version (\d+)\.(\d+)\.(\d+)/),
            let major = Int(match.1), let minor = Int(match.2), let patch = Int(match.3)
        else { return nil }
        self.init(major: major, minor: minor, patch: patch)
    }

    var isSupported: Bool { self >= Self.minimumSupported }

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (lhs: GhVersion, rhs: GhVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
