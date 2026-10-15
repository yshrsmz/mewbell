import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Mewbell

struct AccountDisclosureTests {
    private static let loaded = FeedPhase.loaded(updatedAt: Date(timeIntervalSince1970: 0))

    private func feed(_ phase: FeedPhase = loaded, threads count: Int)
        throws -> FeedState
    {
        let repository = try #require(RepositoryName(fullName: "octo/app"))
        let threads = (0..<count).map { index in
            NotificationThread(
                id: "\(index + 1)", reason: "subscribed", updatedAt: Date(timeIntervalSince1970: Double(index)),
                title: "Thread \(index + 1)", kind: .issue, subjectURL: nil, repository: repository,
                detailsSubject: nil)
        }
        return FeedState(phase: phase, threads: threads)
    }

    /// トークンの取り直し中や、取得の失敗の後の再試行中も、それまでの一覧を畳んだままにする
    @Test(arguments: [
        (TokenState.ready, loaded),
        (.fetching, loaded),
        (.ready, .retrying(nextAttempt: Date(timeIntervalSince1970: 0), rateLimited: false)),
    ])
    func collapsesWhileShowingThreads(_ tokenState: TokenState, _ phase: FeedPhase) throws {
        let disclosure = AccountDisclosure(
            tokenState: tokenState, feed: try feed(phase, threads: 3), isStoredCollapsed: true)
        #expect(disclosure.showsThreads)
        #expect(disclosure.isCollapsed)
    }

    /// トークンを取れない、最初の取得の前、止まった、取得中（参加のみの切り替えや再開の後）は、畳むものが無い
    @Test(arguments: [
        (TokenState.unavailable, FeedPhase?.some(loaded), 3),
        (.ready, nil, 0),
        (.ready, .unauthorized, 0),
        (.ready, .scopeInsufficient, 0),
        (.ready, .loading, 0),
    ])
    func doesNotCollapseWithoutThreadsShown(_ tokenState: TokenState, _ phase: FeedPhase?, _ count: Int) throws {
        let disclosure = AccountDisclosure(
            tokenState: tokenState, feed: try phase.map { try feed($0, threads: count) }, isStoredCollapsed: true)
        #expect(!disclosure.showsThreads)
        #expect(!disclosure.isCollapsed)
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

    /// 件数は、畳んでいてスレッドがあるときだけ出す。
    @Test(arguments: [(true, 3, Int?.some(3)), (true, 0, nil), (false, 3, nil)])
    func showsTheCountOnlyWhenCollapsedWithThreads(_ isCollapsed: Bool, _ count: Int, _ shown: Int?) {
        #expect(shownCount(isCollapsed: isCollapsed, count: count) == shown)
    }
}

/// 見出しの高さ（開閉の押せる範囲の高さ）。畳めるときも畳めないときも `ListLayout.headingHeight` にそろう
@MainActor
struct DisclosureButtonHeightTests {
    /// アカウントの見出し（`.headline`）とリポジトリの見出し（`.subheadline.weight(.semibold)`）の書体
    private nonisolated static let fonts: [Font] = [.headline, .subheadline.weight(.semibold)]

    @Test(arguments: fonts, [true, false])
    func isTheHeadingHeight(_ font: Font, _ isCollapsible: Bool) {
        let button = DisclosureButton(isCollapsed: true, name: "octo/app", isCollapsible: isCollapsible, count: 3) {
        } label: {
            Text("octo/app").font(font)
        }
        #expect(NSHostingView(rootView: button).fittingSize.height == ListLayout.headingHeight)
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
