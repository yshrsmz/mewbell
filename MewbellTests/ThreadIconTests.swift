import AppKit
import SwiftUI
import Testing

@testable import Mewbell

struct ThreadIconTests {
    @Test func distinguishesStatesByShape() {
        let pulls = [SubjectState.open, .draft, .merged, .closed].map { ThreadIcon(kind: .pullRequest, state: $0) }
        #expect(Set(pulls.map(\.symbol)).count == pulls.count)
        let issues = [SubjectState.open, .closedCompleted, .closedNotPlanned].map {
            ThreadIcon(kind: .issue, state: $0)
        }
        #expect(Set(issues.map(\.symbol)).count == issues.count)
    }

    @Test func labelsTheKindAndState() {
        #expect(ThreadIcon(kind: .issue, state: .closedNotPlanned).label == "Issue, closed as not planned")
    }

    @Test(arguments: [(SubjectKind.pullRequest, "Pull request"), (.issue, "Issue"), (.workflowRun, "Workflow run")])
    func showsOnlyTheKindWithoutAState(_ kind: SubjectKind, _ name: String) {
        let unknown = ThreadIcon(kind: kind, state: nil)
        #expect(unknown.color == nil)
        #expect(unknown.label == name)
    }

    /// 状態が分からなくても、記号で Pull request と Issue を見分けられる
    @Test func keepsTheKindsApartWithoutAState() {
        #expect(ThreadIcon(kind: .pullRequest, state: nil).symbol != ThreadIcon(kind: .issue, state: nil).symbol)
    }

    @Test func fallsBackToTheKindWithoutAMatchingState() {
        // 種類に合わない状態は、状態が無いときと同じ
        #expect(ThreadIcon(kind: .release, state: .open) == ThreadIcon(kind: .release, state: nil))
        #expect(ThreadIcon(kind: .issue, state: .merged) == ThreadIcon(kind: .issue, state: nil))
    }

    /// 状態の色は GitHub の Web と同じ（ui「スレッドの行の状態のアイコンの色」）。nil は薄い色
    @Test(arguments: [
        (SubjectKind.pullRequest, SubjectState.open, ColorResource?.some(.stateOpen)),
        (.pullRequest, .draft, nil),
        (.pullRequest, .merged, .stateDone),
        (.pullRequest, .closed, .stateClosed),
        (.issue, .open, .stateOpen),
        (.issue, .closedCompleted, .stateDone),
        (.issue, .closedNotPlanned, nil),
    ])
    func usesGitHubStateColors(_ kind: SubjectKind, _ state: SubjectState, _ expected: ColorResource?) {
        #expect(ThreadIcon(kind: kind, state: state).color == expected.map { Color($0) })
    }
}

/// 状態の色セットの値は Primer の `fgColor-open`・`fgColor-closed`・`fgColor-done`（ui「スレッドの行の状態のアイコンの色の値」の表）。
/// コントラストを上げたときの外観は `NSAppearance(named:)` で作れない（作ると普通の外観になる）ので、ライトとダークだけを確かめる
struct StateColorTests {
    private static let appearances: [NSAppearance.Name] = [.aqua, .darkAqua]

    @MainActor
    @Test(arguments: [
        (ColorResource.stateOpen, ["1A7F37", "3FB950"]),
        (.stateClosed, ["D1242F", "F85149"]),
        (.stateDone, ["8250DF", "AB7DF8"]),
    ])
    func matchesPrimer(_ resource: ColorResource, _ expected: [String]) {
        #expect(Self.appearances.map { hex(NSColor(resource: resource), in: $0) } == expected)
    }

    /// 外観を当てて解決した色の sRGB の値（`RRGGBB`）
    @MainActor
    private func hex(_ color: NSColor, in name: NSAppearance.Name) -> String? {
        var result: String?
        NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
            guard let srgb = color.usingColorSpace(.sRGB) else { return }
            result = [srgb.redComponent, srgb.greenComponent, srgb.blueComponent]
                .map { String(format: "%02X", Int(($0 * 255).rounded())) }
                .joined()
        }
        return result
    }
}
