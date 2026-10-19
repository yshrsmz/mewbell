import Testing

@testable import Mewbell

struct ThreadEventTextTests {
    @Test func namesEveryEvent() {
        let names = ThreadEvent.Kind.allCases.map(ThreadEventText.name)
        #expect(Set(names).count == ThreadEvent.Kind.allCases.count)
        #expect(names.allSatisfy { !$0.isEmpty })
    }

    /// 検証を通らないログイン名は出さない。
    @Test(arguments: [
        (ThreadEvent(kind: .closed, actor: "alice"), "Closed by alice"),
        (ThreadEvent(kind: .pushedCommits, actor: nil), "Pushed commits"),
        (ThreadEvent(kind: .closed, actor: "-evil"), "Closed"),
    ])
    func describesEvents(_ event: ThreadEvent, _ text: String) {
        #expect(ThreadEventText.text(event) == text)
    }
}
