import Testing

@testable import Mewbell

struct RepositoryActionLabelsTests {
    @Test func namesTheRepositoryAndTheCount() {
        let labels = RepositoryActionLabels(repository: "octo/app", count: 2)
        #expect(labels.read == "Mark all in octo/app as read")
        #expect(labels.confirmation == "Mark 2 as done?")
        #expect(labels.doneHelp(confirming: false) == "Mark all in octo/app as done")
        #expect(labels.doneHelp(confirming: true) == "Click again to mark 2 in octo/app as done")
        #expect(labels.doneAccessibilityLabel(confirming: false) == "Mark all in octo/app as done")
        #expect(labels.doneAccessibilityLabel(confirming: true) == "Confirm marking 2 in octo/app as done")
    }
}
