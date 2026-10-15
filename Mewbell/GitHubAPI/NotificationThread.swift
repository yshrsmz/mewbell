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

/// スレッドの件名の詳細を取りに行く先。番号とリリースの ID は排他（Release は番号の代わりにタグを取る）。
enum DetailsSubject: Hashable, Sendable {
    /// Issue・Pull request の番号（一覧に `#<番号>` を出し、状態とイベントを取る）
    case number(String)
    /// Release のリリースの ID（タグを取る）
    case release(id: String)
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
    /// 件名の詳細を取りに行く先。読み取るときに `ThreadWebURL.detailsSubject` で求める（検証を通らなければ nil）
    let detailsSubject: DetailsSubject?
    /// 件名の状態とイベント（Release ではタグ）。API のデコードでは nil で、ポーラーが取得した後に付ける
    var details: ThreadDetails?
}

extension NotificationThread {
    /// `GET /notifications` のレスポンスボディを読む。形の崩れたスレッドは 1 件ずつ読み飛ばす。
    /// ボディ全体が JSON の配列でなければ nil。詳細を取りに行く先（`detailsSubject`）は `endpoints` で求める。
    static func decodeList(from data: Data, endpoints: APIEndpoints) -> [NotificationThread]? {
        APIJSON.decodeArray(ThreadDTO.self, from: data)?.compactMap { $0.thread(endpoints: endpoints) }
    }
}

/// API のレスポンスボディ（JSON、キーは snake_case）の読み方。
enum APIJSON {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    /// JSON の配列を読む。形の崩れた要素は 1 件ずつ読み飛ばす。ボディ全体が JSON の配列でなければ nil。
    static func decodeArray<Element: Decodable>(_: Element.Type, from data: Data) -> [Element]? {
        (try? decoder().decode([Lenient<Element>].self, from: data))?.compactMap(\.value)
    }

    /// 1 件のデコードに失敗しても配列全体を失敗させないための入れ物。
    private struct Lenient<Value: Decodable>: Decodable {
        let value: Value?

        init(from decoder: any Decoder) throws {
            value = try? Value(from: decoder)
        }
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

    /// 検証を通ったスレッド。通らなければ nil。
    func thread(endpoints: APIEndpoints) -> NotificationThread? {
        guard !id.isEmpty, let repository = RepositoryName(fullName: repository.fullName),
            let updatedAt = try? Date(updatedAt, strategy: .iso8601)
        else { return nil }
        let kind = SubjectKind(apiValue: subject.type)
        let subjectURL = subject.url.flatMap(URL.init(string:))
        return NotificationThread(
            id: id, reason: reason ?? "", updatedAt: updatedAt, title: subject.title, kind: kind,
            subjectURL: subjectURL, repository: repository,
            detailsSubject: ThreadWebURL.detailsSubject(
                kind: kind, subjectURL: subjectURL, repository: repository, endpoints: endpoints))
    }
}
