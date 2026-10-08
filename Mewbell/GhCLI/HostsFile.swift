import Foundation
import Yams
import os

/// gh の設定ディレクトリ。
enum GhConfigDirectory {
    /// `GH_CONFIG_DIR` → `XDG_CONFIG_HOME/gh` → `~/.config/gh` の順に決める（gh と同じ順）。
    static func resolve(environment: [String: String], homeDirectory: URL) -> URL {
        if let directory = environment["GH_CONFIG_DIR"], !directory.isEmpty {
            return URL(filePath: directory, directoryHint: .isDirectory)
        }
        if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            return URL(filePath: xdg, directoryHint: .isDirectory).appending(path: "gh", directoryHint: .isDirectory)
        }
        return homeDirectory.appending(path: ".config/gh", directoryHint: .isDirectory)
    }
}

/// `hosts.yml` から読んだ値の検証。gh の引数に渡す前に必ず通す。
enum GhIdentifier {
    /// DNS 名として妥当なホスト名（英数字とハイフンのラベルをドットでつなぐ。全体 253 文字以下）。
    static func isValidHost(_ host: String) -> Bool {
        guard (1...253).contains(host.utf8.count), !host.hasPrefix("-") else { return false }
        return host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            (1...63).contains(label.utf8.count) && !label.hasPrefix("-") && !label.hasSuffix("-")
                && label.unicodeScalars.allSatisfy { $0.isASCII && ($0.properties.isAlphabetic || isDigitOrHyphen($0)) }
        }
    }

    /// GitHub のログイン名として受け入れる値（英数字・`-`・`_` の 1〜100 文字。EMU の `_shortcode` を含む）。
    static func isValidUser(_ user: String) -> Bool {
        guard (1...100).contains(user.utf8.count), !user.hasPrefix("-") else { return false }
        return user.unicodeScalars.allSatisfy {
            $0.isASCII && ($0.properties.isAlphabetic || isDigitOrHyphen($0) || $0 == "_")
        }
    }

    private static func isDigitOrHyphen(_ scalar: Unicode.Scalar) -> Bool {
        ("0"..."9").contains(scalar) || scalar == "-"
    }
}

/// `hosts.yml` の中身のうち、ホスト名とユーザー名だけ。トークンなどほかのキーは型に載せない。
struct HostsFile: Sendable, Equatable {
    struct Host: Sendable, Equatable {
        /// 小文字にそろえたホスト名
        let name: String
        let users: [String]
        let activeUser: String?
    }

    enum LoadError: Error, Equatable {
        case tooLarge
        case unreadable
        case malformed
    }

    static let sizeLimit = 1024 * 1024

    private static let logger = Logger(category: "GhCLI")

    let hosts: [Host]

    /// ファイルを読む。ファイルが無いときは nil（未ログイン）。
    static func load(from url: URL) throws(LoadError) -> HostsFile? {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            let nsError = error as NSError
            let missing =
                (nsError.domain == NSCocoaErrorDomain
                    && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(nsError.code))
                || (nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOENT))
            if missing { return nil }
            throw .unreadable
        }
        defer { try? handle.close() }

        let data: Data
        do {
            data = try handle.read(upToCount: sizeLimit + 1) ?? Data()
        } catch {
            throw .unreadable
        }
        guard data.count <= sizeLimit else { throw .tooLarge }
        guard let text = String(data: data, encoding: .utf8) else { throw .malformed }
        return try parse(text)
    }

    /// 複数アカウントの形式（`users:` の下にユーザー名）と、それ以前の形式（`user:` だけ）を読む。
    /// 検証を通らないホストとユーザーは読み飛ばす。
    static func parse(_ text: String) throws(LoadError) -> HostsFile {
        let root: Node?
        do {
            root = try Yams.compose(yaml: text)
        } catch {
            throw .malformed
        }
        guard let root else { return HostsFile(hosts: []) }
        guard let mapping = root.mapping else { throw .malformed }

        var hosts: [Host] = []
        for (key, value) in mapping {
            guard let rawName = key.scalar?.string, GhIdentifier.isValidHost(rawName) else {
                logger.info("Skipped a host entry with an invalid name")
                continue
            }
            let name = rawName.lowercased()
            guard !hosts.contains(where: { $0.name == name }), let entry = value.mapping else { continue }

            let activeUser = entry["user"]?.scalar?.string
            let listedUsers: [String]
            if let users = entry["users"]?.mapping, !users.isEmpty {
                listedUsers = users.compactMap { $0.key.scalar?.string }
            } else {
                listedUsers = activeUser.map { [$0] } ?? []
            }
            var users: [String] = []
            // GitHub のログイン名は大文字・小文字を区別しないので、大文字・小文字だけが違う名前は 1 つにまとめる
            for user in listedUsers where !users.contains(where: { $0.lowercased() == user.lowercased() }) {
                if GhIdentifier.isValidUser(user) {
                    users.append(user)
                } else {
                    logger.info("Skipped a user entry with an invalid name on \(name)")
                }
            }
            guard !users.isEmpty else { continue }
            hosts.append(
                Host(name: name, users: users, activeUser: users.first { $0.lowercased() == activeUser?.lowercased() }))
        }
        return HostsFile(hosts: hosts)
    }
}
