import Foundation
import Testing

@testable import Mewbell

private func thread(_ id: String, updatedAt: TimeInterval = 0) throws -> NotificationThread {
    NotificationThread(
        id: id, reason: "subscribed", updatedAt: Date(timeIntervalSince1970: updatedAt),
        title: "Thread \(id) at \(updatedAt)",
        kind: .issue, subjectURL: nil, repository: try #require(RepositoryName(fullName: "octo/app")),
        detailsSubject: nil)
}

/// 条件付きの `200` を今の一覧に重ねる。
struct ThreadListMergeTests {
    @Test func replacesTheSameIDAddsNewOnesAndKeepsTheRest() throws {
        let current = [
            try thread("1", updatedAt: 100), try thread("2", updatedAt: 200), try thread("3", updatedAt: 300),
        ]
        let fetched = [try thread("4", updatedAt: 500), try thread("2", updatedAt: 400)]

        let merged = ThreadListMerge.merge(fetched, into: current)

        #expect(merged.map(\.id) == ["4", "2", "1", "3"])
        let replaced = try #require(merged.first { $0.id == "2" })
        #expect(replaced.updatedAt == Date(timeIntervalSince1970: 400))
        #expect(replaced.title == "Thread 2 at 400.0")
    }

    @Test func keepsTheCurrentListWhenNothingIsFetched() throws {
        let current = [try thread("1"), try thread("2")]
        #expect(ThreadListMerge.merge([], into: current) == current)
    }

    @Test func returnsTheFetchedThreadsWhenTheListIsEmpty() throws {
        let fetched = [try thread("1"), try thread("2")]
        #expect(ThreadListMerge.merge(fetched, into: []) == fetched)
    }
}
