import Foundation

extension URL {
    /// クエリに `name=value` を足した URL。値は `URLQueryItem` と同じくエスケープし、`+` も `%2B` に、`;` も `%3B` にする
    /// （`+` が空白として、`;` が区切りとして読まれないように）。
    func appending(queryValue value: String, for name: String) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        var escaped = URLComponents()
        escaped.queryItems = [URLQueryItem(name: name, value: value)]
        let item = (escaped.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B")
            .replacingOccurrences(of: ";", with: "%3B")
        components.percentEncodedQuery = [components.percentEncodedQuery, item].compactMap { $0 }.joined(separator: "&")
        return components.url ?? self
    }
}
