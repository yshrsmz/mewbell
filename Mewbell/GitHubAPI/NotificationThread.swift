import Foundation

/// 検証済みのリポジトリ名（`owner/name`）。
struct RepositoryName: Hashable, Sendable, CustomStringConvertible {
    let owner: String
    let name: String

    /// `owner/name` の形で、owner は GitHub のログイン名、name はリポジトリ名に使える文字だけのときに作る。
    init?(fullName: String) {
        let parts = fullName.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        self.init(owner: String(parts[0]), name: String(parts[1]))
    }

    init?(owner: String, name: String) {
        guard GhIdentifier.isValidUser(owner), Self.isValidName(name) else { return nil }
        self.owner = owner
        self.name = name
    }

    var description: String { "\(owner)/\(name)" }

    /// 英数字・`-`・`_`・`.` の 1〜100 文字。`.` と `..` は拒否する。
    private static func isValidName(_ name: String) -> Bool {
        guard (1...100).contains(name.utf8.count), name != ".", name != ".." else { return false }
        return name.unicodeScalars.allSatisfy {
            $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0) || "-_.".unicodeScalars.contains($0))
        }
    }

    /// 大文字小文字を無視して同じリポジトリか。
    func matches(_ other: RepositoryName) -> Bool {
        owner.lowercased() == other.owner.lowercased() && name.lowercased() == other.name.lowercased()
    }
}

/// 通知の件名の種類（`subject.type`）。
enum SubjectKind: Hashable, Sendable {
    case pullRequest
    case issue
    case commit
    case release
    case discussion
    case checkSuite
    case other(String)

    init(apiValue: String) {
        self =
            switch apiValue {
            case "PullRequest": .pullRequest
            case "Issue": .issue
            case "Commit": .commit
            case "Release": .release
            case "Discussion": .discussion
            case "CheckSuite": .checkSuite
            default: .other(apiValue)
            }
    }
}

/// 未読の通知スレッド。API のレスポンスから、検証を通ったものだけを作る。
struct NotificationThread: Hashable, Sendable, Identifiable {
    let id: String
    let reason: String
    let updatedAt: Date
    let title: String
    let kind: SubjectKind
    /// `subject.url`（API の URL。Web で開くときは `ThreadWebURL` で組み立て直す）
    let subjectURL: URL?
    let repository: RepositoryName
    /// 一覧に出す Issue・Pull request の番号。取得したときに `ThreadWebURL.subjectNumber` で求める。
    /// 開く URL と同じ検証を通らなければ nil
    var subjectNumber: String?
}

extension NotificationThread {
    /// `GET /notifications` のレスポンスボディを読む。形の崩れたスレッドは 1 件ずつ読み飛ばす。
    /// ボディ全体が JSON の配列でなければ nil。
    static func decodeList(from data: Data) -> [NotificationThread]? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let items = try? decoder.decode([LenientThread].self, from: data) else { return nil }
        return items.compactMap { $0.value }
    }
}

/// 1 件のデコードに失敗しても配列全体を失敗させないための入れ物。
private struct LenientThread: Decodable {
    let value: NotificationThread?

    init(from decoder: any Decoder) throws {
        value = (try? ThreadDTO(from: decoder)).flatMap(\.thread)
    }
}

private struct ThreadDTO: Decodable {
    struct Subject: Decodable {
        let title: String
        let url: String?
        let type: String
    }

    struct Repository: Decodable {
        let fullName: String
    }

    let id: String
    let reason: String?
    let updatedAt: String
    let subject: Subject
    let repository: Repository

    var thread: NotificationThread? {
        guard !id.isEmpty, let repository = RepositoryName(fullName: repository.fullName),
            let updatedAt = try? Date(updatedAt, strategy: .iso8601)
        else { return nil }
        return NotificationThread(
            id: id, reason: reason ?? "", updatedAt: updatedAt, title: subject.title,
            kind: SubjectKind(apiValue: subject.type), subjectURL: subject.url.flatMap(URL.init(string:)),
            repository: repository)
    }
}
