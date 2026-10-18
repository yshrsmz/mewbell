import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Mewbell

struct AccountDisclosureTests {
    private static let loaded = FeedPhase.loaded(updatedAt: Date(timeIntervalSince1970: 0))

    /// 3 件のスレッドを持つ一覧（一覧を出すかどうかは、件数ではなく状態で決まる）
    private func feed(_ phase: FeedPhase) throws -> FeedState {
        let repository = try #require(RepositoryName(fullName: "octo/app"))
        let threads = (0..<3).map { index in
            NotificationThread(
                id: "\(index + 1)", reason: "subscribed", updatedAt: Date(timeIntervalSince1970: Double(index)),
                title: "Thread \(index + 1)", kind: .issue, subjectURL: nil, repository: repository,
                detailsSubject: nil)
        }
        return FeedState(phase: phase, threads: threads)
    }

    /// 一覧を出しているときだけ、覚えている開閉で畳む。トークンの取り直し中や、取得の失敗の後の再試行中も一覧を出す。
    /// トークンを取れない、最初の取得の前、止まった、取得中（参加のみの切り替えや再開の後）は、畳むものが無い
    @Test(arguments: [
        (
            TokenState.fetching,
            FeedPhase?.some(.retrying(nextAttempt: Date(timeIntervalSince1970: 0), rateLimited: false)), true, true,
            true
        ),
        (.ready, loaded, false, true, false),
        (.unavailable, loaded, true, false, false),
        (.ready, nil, true, false, false),
        (.ready, .unauthorized, true, false, false),
        (.ready, .scopeInsufficient, true, false, false),
        (.ready, .loading, true, false, false),
    ])
    func collapsesOnlyWhileShowingThreads(
        _ tokenState: TokenState, _ phase: FeedPhase?, _ isStoredCollapsed: Bool, _ showsThreads: Bool,
        _ isCollapsed: Bool
    ) throws {
        let disclosure = AccountDisclosure(
            tokenState: tokenState, feed: try phase.map(feed),
            isStoredCollapsed: isStoredCollapsed)
        #expect(disclosure.showsThreads == showsThreads)
        #expect(disclosure.isCollapsed == isCollapsed)
    }
}

struct DisclosureButtonCountTests {
    private func shownCount(isCollapsed: Bool, count: Int) -> Int? {
        DisclosureButton<EmptyView, EmptyView>.shownCount(isCollapsed: isCollapsed, count: count)
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

    /// アカウントの見出しと同じく、中央に置くアイコンと、ベースラインで揃える大きさの違う文字（上下に余白のある
    /// アクティブの印と参加のみの印を含む）を並べても高くならない
    @Test(arguments: [true, false])
    func staysTheHeadingHeightWithAnIconAndMixedText(_ isCollapsible: Bool) {
        let button = DisclosureButton(isCollapsed: true, name: "alice", isCollapsible: isCollapsible, count: 3) {
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .frame(width: ListLayout.iconColumnWidth)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: ListLayout.spacing) {
                Text("alice").font(.headline)
                Text("active").font(.subheadline).capsuleBadge(.tint.opacity(0.15))
                Text("github.com").font(.subheadline)
                Image(systemName: "person.crop.circle.badge.checkmark").font(.subheadline)
            }
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
