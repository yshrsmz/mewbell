import Foundation
import Yams
import os

/// gh の設定ディレクトリ。
enum GhConfigDirectory {
    /// 設定ディレクトリを決めた方法。
    enum Source: Sendable, Equatable {
        /// 設定で上書きしたディレクトリ
        case override
        /// 環境変数 `GH_CONFIG_DIR`
        case ghConfigDir
        /// 環境変数 `XDG_CONFIG_HOME`
        case xdgConfigHome
        /// 既定の `~/.config/gh`
        case defaultLocation
    }

    /// 決めた設定ディレクトリと、その方法。
    struct Resolved: Sendable, Equatable {
        let url: URL
        let source: Source
    }

    /// `GH_CONFIG_DIR` → `XDG_CONFIG_HOME/gh` → `~/.config/gh` の順に決める（gh と同じ順）。
    static func resolve(environment: [String: String], homeDirectory: URL) -> Resolved {
        if let directory = environment["GH_CONFIG_DIR"], !directory.isEmpty {
            return Resolved(url: URL(filePath: directory, directoryHint: .isDirectory), source: .ghConfigDir)
        }
        if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            return Resolved(
                url: URL(filePath: xdg, directoryHint: .isDirectory).appending(path: "gh", directoryHint: .isDirectory),
                source: .xdgConfigHome)
        }
        return Resolved(
            url: homeDirectory.appending(path: ".config/gh", directoryHint: .isDirectory), source: .defaultLocation)
    }
}

/// 設定で上書きした gh の設定ディレクトリの検証。
enum ConfigDirectoryValidator {
    /// 使えるとき、シンボリックリンクを解決した実体のディレクトリを返す。絶対パスで、実体がディレクトリで、
    /// 所有者が現在のユーザーで、world-writable でないこと。確かめた後にリンクを差し替えられないよう、使うのは返した実体にする。
    static func validate(_ path: String) -> URL? {
        guard path.hasPrefix("/"), let resolvedPointer = realpath(path, nil) else { return nil }
        let resolved = String(cString: resolvedPointer)
        free(resolvedPointer)
        var info = stat()
        guard stat(resolved, &info) == 0,
            info.st_mode & S_IFMT == S_IFDIR,
            info.st_uid == getuid(),
            info.st_mode & S_IWOTH == 0
        else { return nil }
        return URL(filePath: resolved, directoryHint: .isDirectory)
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
        // 通常ファイル以外（FIFO など）は開かない。FIFO は開くだけで止まり、アプリを終了できなくなる
        var info = stat()
        guard stat(url.path, &info) == 0 else {
            if errno == ENOENT { return nil }
            throw .unreadable
        }
        guard info.st_mode & S_IFMT == S_IFREG else { throw .unreadable }

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            // 無いことは直前の stat で確かめているので、ここでの失敗（直前に消えた場合も含む）は読めない扱いにする
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
