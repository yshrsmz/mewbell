import Foundation

/// gh から受け取ったアカウントのトークン。
///
/// 文字列にしたとき（文字列補間・`debugPrint`・`dump`・`Mirror`）は伏せ字になる。
/// `Codable` には準拠させない（ディスクやログへ書き出す経路を作らないため）。
struct AccessToken: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// `Authorization` ヘッダーを作るときだけ読む（M2）
    let value: String

    /// `gh auth token` の標準出力から作る。前後の空白を除いて、空でなく空白文字を含まない 1 行のときだけ受け入れる。
    init?(ghOutput: Data) {
        guard let text = String(data: ghOutput, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 表示可能な ASCII（空白と制御文字を除く）だけからなるときに受け入れる
        guard !trimmed.isEmpty, trimmed.unicodeScalars.allSatisfy({ (0x21..<0x7F).contains($0.value) }) else {
            return nil
        }
        value = trimmed
    }

    var description: String { "AccessToken(<redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
}

/// ログに残す文字列から、トークンらしい部分を伏せ字にする。
enum Redaction {
    static let placeholder = "<redacted>"

    static func redactTokens(in text: String) -> String {
        text.replacing(/(?:gh[opsu]_|github_pat_)[A-Za-z0-9_]+/, with: placeholder)
    }
}
