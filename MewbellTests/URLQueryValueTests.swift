import Foundation
import Testing

@testable import Mewbell

/// クエリの値のエスケープ（`+` も `%2B` に、`;` も `%3B` にする）。
struct URLQueryValueTests {
    private let base: URL

    init() throws {
        base = try #require(URL(string: "https://github.com/octo/app/actions"))
    }

    @Test(arguments: [
        ("is:waiting", "query=is:waiting"),
        (
            #"workflow:"Build and test" is:failure branch:feat/a+b"#,
            "query=workflow:%22Build%20and%20test%22%20is:failure%20branch:feat/a%2Bb"
        ),
        ("a&b=c#d", "query=a%26b%3Dc%23d"),
        ("feat;x", "query=feat%3Bx"),
    ])
    func escapesTheValue(_ value: String, _ query: String) {
        let url = base.appending(queryValue: value, for: "query")
        #expect(url.absoluteString == "https://github.com/octo/app/actions?\(query)")
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == value)
    }

    @Test func keepsTheExistingQuery() throws {
        let url = try #require(URL(string: "https://api.github.com/repos/octo/app/actions/runs?status=waiting"))
            .appending(queryValue: "20", for: "per_page")
        #expect(url.absoluteString == "https://api.github.com/repos/octo/app/actions/runs?status=waiting&per_page=20")
    }
}
