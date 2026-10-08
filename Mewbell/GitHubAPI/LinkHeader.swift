import Foundation

/// `Link` ヘッダー（RFC 8288）のうち、ページネーションに使う `rel="next"` だけを読む。
enum LinkHeader {
    /// `<https://...>; rel="next", <https://...>; rel="last"` から `next` の URL を返す。無ければ nil。
    static func nextURL(in header: String?) -> URL? {
        guard let header else { return nil }
        for link in header.split(separator: ",") {
            let parts = link.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let target = parts.first, target.hasPrefix("<"), target.hasSuffix(">") else { continue }
            let isNext = parts.dropFirst().contains { parameter in
                let pair = parameter.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                guard pair.count == 2, pair[0].lowercased() == "rel" else { return false }
                let relations = pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                return relations.split(separator: " ").contains { $0.lowercased() == "next" }
            }
            if isNext {
                return URL(string: String(target.dropFirst().dropLast()))
            }
        }
        return nil
    }
}
