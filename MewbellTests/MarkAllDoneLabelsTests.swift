import Testing

@testable import Mewbell

struct MarkAllDoneLabelsTests {
    @Test func namesTheCount() {
        let labels = MarkAllDoneLabels(count: 3)
        #expect(MarkAllDoneLabels.done == "Mark all as done")
        #expect(labels.confirmation == "Mark 3 as done?")
        #expect(labels.help(confirming: false) == "Mark all as done")
        #expect(labels.help(confirming: true) == "Click again to mark 3 as done")
        #expect(labels.accessibilityLabel(confirming: false) == "Mark all as done")
        #expect(labels.accessibilityLabel(confirming: true) == "Confirm marking 3 as done")
    }
}
