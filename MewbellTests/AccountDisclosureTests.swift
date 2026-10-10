import Foundation
import Testing

@testable import Mewbell

struct AccountDisclosureTests {
    private func feed(_ phase: FeedPhase = .loaded(updatedAt: Date(timeIntervalSince1970: 0)), threads count: Int)
        throws -> FeedState
    {
        let repository = try #require(RepositoryName(fullName: "octo/app"))
        let threads = (0..<count).map { index in
            NotificationThread(
                id: "\(index + 1)", reason: "subscribed", updatedAt: Date(timeIntervalSince1970: Double(index)),
                title: "Thread \(index + 1)", kind: .issue, subjectURL: nil, repository: repository)
        }
        return FeedState(phase: phase, threads: threads)
    }

    @Test func collapsesAReadyAccountWithThreadsAndShowsTheCount() throws {
        let disclosure = AccountDisclosure(tokenState: .ready, feed: try feed(threads: 3), isStoredCollapsed: true)
        #expect(disclosure.isCollapsible)
        #expect(disclosure.isCollapsed)
        #expect(disclosure.collapsedCount == 3)
    }

    @Test func hidesTheCountWhenThereAreNoThreads() throws {
        let disclosure = AccountDisclosure(tokenState: .ready, feed: try feed(threads: 0), isStoredCollapsed: true)
        #expect(disclosure.isCollapsed)
        #expect(disclosure.collapsedCount == nil)
    }

    @Test func doesNotCollapseOrCountWhenTheTokenIsUnavailable() throws {
        let disclosure = AccountDisclosure(
            tokenState: .unavailable, feed: try feed(threads: 3), isStoredCollapsed: true)
        #expect(!disclosure.isCollapsible)
        #expect(!disclosure.isCollapsed)
        #expect(disclosure.collapsedCount == nil)
    }

    @Test func doesNotCollapseBeforeTheFirstFeed() {
        let disclosure = AccountDisclosure(tokenState: .ready, feed: nil, isStoredCollapsed: true)
        #expect(!disclosure.isCollapsible)
        #expect(!disclosure.isCollapsed)
    }

    @Test func doesNotCollapseAStoppedFeed() throws {
        let disclosure = AccountDisclosure(
            tokenState: .ready, feed: try feed(.unauthorized, threads: 0), isStoredCollapsed: true)
        #expect(!disclosure.isCollapsible)
        #expect(!disclosure.isCollapsed)
    }

    @Test func showsNoCountWhenExpanded() throws {
        let disclosure = AccountDisclosure(tokenState: .ready, feed: try feed(threads: 3), isStoredCollapsed: false)
        #expect(disclosure.isCollapsible)
        #expect(!disclosure.isCollapsed)
        #expect(disclosure.collapsedCount == nil)
    }
}
