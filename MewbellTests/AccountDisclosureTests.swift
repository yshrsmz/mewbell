import Foundation
import SwiftUI
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
                title: "Thread \(index + 1)", kind: .issue, subjectURL: nil, repository: repository,
                subjectNumber: nil)
        }
        return FeedState(phase: phase, threads: threads)
    }

    @Test func collapsesAReadyAccountWithThreads() throws {
        let disclosure = AccountDisclosure(tokenState: .ready, feed: try feed(threads: 3), isStoredCollapsed: true)
        #expect(disclosure.showsThreads)
        #expect(disclosure.isCollapsed)
    }

    @Test func collapsesAReadyAccountWithNoThreads() throws {
        let disclosure = AccountDisclosure(tokenState: .ready, feed: try feed(threads: 0), isStoredCollapsed: true)
        #expect(disclosure.showsThreads)
        #expect(disclosure.isCollapsed)
    }

    @Test func doesNotCollapseWhenTheTokenIsUnavailable() throws {
        let disclosure = AccountDisclosure(
            tokenState: .unavailable, feed: try feed(threads: 3), isStoredCollapsed: true)
        #expect(!disclosure.showsThreads)
        #expect(!disclosure.isCollapsed)
    }

    @Test func doesNotCollapseBeforeTheFirstFeed() {
        let disclosure = AccountDisclosure(tokenState: .ready, feed: nil, isStoredCollapsed: true)
        #expect(!disclosure.showsThreads)
        #expect(!disclosure.isCollapsed)
    }

    @Test(arguments: [FeedPhase.unauthorized, .scopeInsufficient])
    func doesNotCollapseAStoppedFeed(_ phase: FeedPhase) throws {
        let disclosure = AccountDisclosure(
            tokenState: .ready, feed: try feed(phase, threads: 0), isStoredCollapsed: true)
        #expect(!disclosure.showsThreads)
        #expect(!disclosure.isCollapsed)
    }

    /// 参加のみの切り替えや再開の後の取得中は、畳むものが無い
    @Test func doesNotCollapseWhileLoading() throws {
        let disclosure = AccountDisclosure(
            tokenState: .ready, feed: try feed(.loading, threads: 0), isStoredCollapsed: true)
        #expect(!disclosure.showsThreads)
        #expect(!disclosure.isCollapsed)
    }

    /// トークンの取り直し中も、それまでの一覧を畳んだままにする
    @Test func keepsCollapsedWhileTheTokenIsBeingFetchedAgain() throws {
        let disclosure = AccountDisclosure(tokenState: .fetching, feed: try feed(threads: 2), isStoredCollapsed: true)
        #expect(disclosure.showsThreads)
        #expect(disclosure.isCollapsed)
    }

    @Test func staysExpandedWhenNotStoredCollapsed() throws {
        let disclosure = AccountDisclosure(tokenState: .ready, feed: try feed(threads: 3), isStoredCollapsed: false)
        #expect(disclosure.showsThreads)
        #expect(!disclosure.isCollapsed)
    }
}

struct DisclosureButtonCountTests {
    private func shownCount(isCollapsed: Bool, count: Int) -> Int? {
        DisclosureButton<EmptyView>.shownCount(isCollapsed: isCollapsed, count: count)
    }

    @Test func showsTheCountWhenCollapsed() {
        #expect(shownCount(isCollapsed: true, count: 3) == 3)
    }

    @Test func showsNoCountWhenCollapsedWithNoThreads() {
        #expect(shownCount(isCollapsed: true, count: 0) == nil)
    }

    @Test func showsNoCountWhenExpanded() {
        #expect(shownCount(isCollapsed: false, count: 3) == nil)
    }
}

@MainActor
struct DisclosureAnimationsTests {
    @Test func countsOverlappingAnimations() {
        let animations = DisclosureAnimations()
        animations.begin()
        animations.begin()
        animations.end()
        #expect(animations.running == 1)
        animations.end()
        #expect(animations.running == 0)
    }

    /// 開き直しで捨てた後に、前のアニメーションの終わりが届いても 0 より下がらない。
    @Test func staysAtZeroWhenAnEndArrivesAfterReset() {
        let animations = DisclosureAnimations()
        animations.begin()
        animations.reset()
        animations.end()
        #expect(animations.running == 0)
        animations.begin()
        #expect(animations.running == 1)
    }
}
