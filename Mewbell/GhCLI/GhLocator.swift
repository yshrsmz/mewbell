import Foundation
import os

/// gh 実行ファイルの候補を検証する。
enum ExecutableValidator {
    /// 候補が使えるとき、シンボリックリンクを解決した実体のパスを返す。
    /// 絶対パスで、実体が通常ファイルで、現在のユーザーが実行でき、他人が書き換えられないことを確かめる。
    /// 他人が書き換えられないとは、ファイルの所有者が自分か root で group / world に書き込み権が無く、
    /// ファイルを置いたディレクトリが world-writable でないこと（Homebrew の `bin` は admin グループの 775 なので、group は許す）。
    static func validate(_ path: String) -> URL? {
        guard path.hasPrefix("/"), let resolvedPointer = realpath(path, nil) else { return nil }
        let resolved = String(cString: resolvedPointer)
        free(resolvedPointer)

        var info = stat()
        guard stat(resolved, &info) == 0,
            info.st_mode & S_IFMT == S_IFREG,
            info.st_uid == getuid() || info.st_uid == 0,
            info.st_mode & (S_IWGRP | S_IWOTH) == 0,
            access(resolved, X_OK) == 0
        else { return nil }
        // 他人が書き込めるディレクトリにあると、ファイルを差し替えられる
        var directoryInfo = stat()
        let directory = URL(filePath: resolved).deletingLastPathComponent().path
        guard stat(directory, &directoryInfo) == 0, directoryInfo.st_mode & S_IWOTH == 0 else { return nil }
        return URL(filePath: resolved)
    }
}

/// ユーザーのログインシェル。
enum LoginShell {
    /// ユーザーアカウントに登録されたシェルが `/etc/shells` に載っていれば、そのパスを返す。
    static func current(shellsFile: String = "/etc/shells") -> String? {
        guard let entry = getpwuid(getuid()), let shellPointer = entry.pointee.pw_shell else { return nil }
        let allowed = (try? String(contentsOfFile: shellsFile, encoding: .utf8)) ?? ""
        return resolve(userShell: String(cString: shellPointer), allowedShells: allowed)
    }

    static func resolve(userShell: String, allowedShells: String) -> String? {
        let allowed = allowedShells.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        guard userShell.hasPrefix("/"), allowed.contains(userShell) else { return nil }
        return userShell
    }

    /// `command -v gh` の出力の最後の空でない行（rc ファイルが出力した行は読み飛ばす）。
    static func lastNonEmptyLine(of output: Data) -> String? {
        guard let text = String(bytes: output, encoding: .utf8) else { return nil }
        return text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
    }
}

/// gh 実行ファイルを探す。ログインシェルでの検索はアプリの起動から終了までに 1 回だけ行う。
actor GhLocator {
    static let defaultCandidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]

    private static let logger = Logger(category: "GhCLI")

    private let candidates: [String]
    private let runner: any ProcessRunning
    private let environment: [String: String]
    private let loginShell: @Sendable () -> String?
    /// ログインシェルでの検索。最初に必要になったときに 1 回だけ始め、同時に呼ばれても同じ結果を待つ
    /// （呼び出し側がキャンセルされても検索は止まらないが、5 秒のタイムアウトで終わる）
    private var loginShellSearch: Task<String?, Never>?

    init(
        candidates: [String] = GhLocator.defaultCandidates,
        runner: any ProcessRunning,
        environment: [String: String],
        loginShell: @escaping @Sendable () -> String? = { LoginShell.current() }
    ) {
        self.candidates = candidates
        self.runner = runner
        self.environment = environment
        self.loginShell = loginShell
    }

    /// 使える gh の実体のパス。`overridePath` があるときは、それだけを確かめる（M4 で設定から渡す）。
    func locate(overridePath: String? = nil) async -> URL? {
        if let overridePath {
            return ExecutableValidator.validate(overridePath)
        }
        for candidate in candidates {
            if let url = ExecutableValidator.validate(candidate) {
                return url
            }
        }
        let search = loginShellSearch ?? Task { await searchLoginShell() }
        loginShellSearch = search
        return await search.value.flatMap(ExecutableValidator.validate)
    }

    private func searchLoginShell() async -> String? {
        guard let shell = loginShell() else {
            Self.logger.info("No usable login shell to look up gh")
            return nil
        }
        let request = ProcessRequest(
            executable: URL(filePath: shell), arguments: ["-i", "-l", "-c", "command -v gh"], environment: environment,
            timeout: .seconds(5), stdoutLimit: 64 * 1024, allowsLingeringPipes: true)
        do {
            let output = try await runner.run(request)
            guard output.exitCode == 0 else { return nil }
            return LoginShell.lastNonEmptyLine(of: output.stdout)
        } catch {
            Self.logger.error("Login shell lookup of gh failed: \(String(describing: error))")
            return nil
        }
    }
}
