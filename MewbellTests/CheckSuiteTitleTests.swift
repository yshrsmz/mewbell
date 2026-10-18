import Foundation
import Testing

@testable import Mewbell

/// 種類が CheckSuite の通知の件名を読む。
struct CheckSuiteTitleTests {
    @Test(arguments: [
        ("CI workflow run failed for main branch", "CI", CheckSuiteTitle.Result.failed, "main"),
        ("CI workflow run failed at startup for main branch", "CI", .failedAtStartup, "main"),
        ("Build and test workflow run, Attempt #2 failed for feat/a+b branch", "Build and test", .failed, "feat/a+b"),
        ("Deploy workflow run failed for release for prod branch", "Deploy", .failed, "release for prod"),
    ])
    func readsTheTitle(_ title: String, _ workflowName: String, _ result: CheckSuiteTitle.Result, _ branch: String)
        throws
    {
        let read = try #require(CheckSuiteTitle(title))
        #expect(read.workflowName == workflowName)
        #expect(read.result == result)
        #expect(read.branch == branch)
    }

    @Test(arguments: [
        "Something happened",
        "CI workflow run exploded for main branch",
        " workflow run failed for main branch",
        "CI workflow run failed for main",
        "CI workflow run, Attempt #\u{662} failed for main branch",
        "C\u{7}I workflow run failed for main branch",
        "\(String(repeating: "a", count: 256)) workflow run failed for main branch",
        "CI workflow run failed for \(String(repeating: "b", count: 256)) branch",
    ])
    func rejectsTheTitle(_ title: String) {
        #expect(CheckSuiteTitle(title) == nil)
    }
}
