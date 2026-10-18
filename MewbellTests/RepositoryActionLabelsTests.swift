import Testing

@testable import Mewbell

struct RepositoryActionLabelsTests {
    @Test func namesTheRepositoryAndTheCount() {
        let labels = RepositoryActionLabels(repository: "octo/app", count: 2)
        #expect(labels.confirmation == "Mark 2 as done?")
        // spec が決めているのは、ツールチップとアクセシビリティのラベルでどのリポジトリへの操作かが分かること
        let named = [
            labels.read, labels.doneHelp(confirming: false), labels.doneHelp(confirming: true),
            labels.doneAccessibilityLabel(confirming: false), labels.doneAccessibilityLabel(confirming: true),
        ]
        #expect(named.allSatisfy { $0.contains("octo/app") })
    }
}
