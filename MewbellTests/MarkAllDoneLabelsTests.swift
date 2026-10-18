import Testing

@testable import Mewbell

struct MarkAllDoneLabelsTests {
    /// spec で決まっているのは確かめの文言だけ。ツールチップとアクセシビリティのラベルの文言は決めていない
    @Test func namesTheCount() {
        #expect(MarkAllDoneLabels(count: 3).confirmation == "Mark 3 as done?")
    }
}
