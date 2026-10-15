import AppKit
import SwiftUI
import Testing

@testable import Mewbell

/// 確かめる種類。`SubjectKind` に case を足すと `listsEvery(_:)` でコンパイルが止まるので、ここにも足す
private let kinds: [SubjectKind] = [
    .pullRequest, .issue, .commit, .release, .discussion, .checkSuite, .workflowRun, .other("CheckRun"),
]

private func listsEvery(_ kind: SubjectKind) {
    // default を置かない（case を足したら一覧に足すまでコンパイルを止める）
    switch kind {
    case .pullRequest, .issue, .commit, .release, .discussion, .checkSuite, .workflowRun, .other: break
    }
}

/// 確かめる状態（分からないときの nil を含む）。`SubjectState` に case を足すと `listsEvery(_:)` でコンパイルが止まるので、ここにも足す
private let states: [SubjectState?] = [nil, .open, .draft, .merged, .closed, .closedCompleted, .closedNotPlanned]

private func listsEvery(_ state: SubjectState?) {
    // default を置かない（case を足したら一覧に足すまでコンパイルを止める）
    switch state {
    case nil, .open, .draft, .merged, .closed, .closedCompleted, .closedNotPlanned: break
    }
}

/// 確かめるトークンの状態。`TokenState` に case を足すと `listsEvery(_:)` でコンパイルが止まるので、ここにも足す
private let tokenStates: [TokenState] = [.fetching, .ready, .unavailable, .disabled]

private func listsEvery(_ tokenState: TokenState) {
    // default を置かない（case を足したら一覧に足すまでコンパイルを止める）
    switch tokenState {
    case .fetching, .ready, .unavailable, .disabled: break
    }
}

/// 確かめる取得の状態。止まっているか（`FeedPhase.isStopped`）で記号が変わるので、両方を含める
private let phases: [FeedPhase?] = [nil, .unauthorized]

/// アイコンの列（`ListLayout.iconColumnWidth`）に置く記号が、書体の大きさのまま列に収まること。
/// 記号は View と同じ書体で、配置の枠（`fittingSize`）を倍率 1 と 2 の画面で測る。
@MainActor
struct IconColumnTests {
    @Test func fitsEveryThreadIcon() {
        let symbols = Set(kinds.flatMap { kind in states.map { ThreadIcon(kind: kind, state: $0).symbol } })
        // スレッドの行は書体を付けない（既定の書体）
        for symbol in symbols.sorted() {
            expectFits(Image(systemName: symbol), symbol)
        }
    }

    /// アカウントの見出しの `tokenIcon` の記号（書体を付けない）。取得中の `ProgressView` は書体で大きさが決まらないので測らない
    @Test func fitsEveryTokenIcon() {
        let symbols = Set(
            tokenStates.flatMap { state in
                phases.compactMap { TokenStateIcon(tokenState: state, phase: $0).symbol }
            })
        for symbol in symbols.sorted() {
            expectFits(Image(systemName: symbol), symbol)
        }
    }

    /// `DisclosureChevron` の山形。90° 回るので、幅と高さの大きいほうが列に収まること
    @Test func fitsTheChevron() {
        expectFits(
            Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)), "chevron.right", rotates: true)
    }

    private func expectFits(
        _ icon: some View, _ symbol: String, rotates: Bool = false, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        for scale: CGFloat in [1, 2] {
            let size = NSHostingView(rootView: icon.environment(\.displayScale, scale)).fittingSize
            let extent = rotates ? max(size.width, size.height) : size.width
            #expect(
                extent <= ListLayout.iconColumnWidth,
                "\(symbol) at @\(Int(scale))x is \(size.width)x\(size.height)pt and does not fit the icon column",
                sourceLocation: sourceLocation)
        }
    }
}
