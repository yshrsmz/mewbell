import Testing

@testable import Mewbell

struct MarkAllReadLabelsTests {
    @Test func showsTheCountWhenEveryUnreadThreadIsListed() {
        let labels = MarkAllReadLabels(count: 3, participatingOnly: false, isTruncated: false)
        #expect(labels.confirmation == "Mark 3 as read?")
        #expect(labels.help(confirming: true) == "Click again to mark all as read")
        #expect(labels.accessibilityLabel(confirming: true) == "Confirm marking 3 as read")
    }

    @Test func hidesTheCountOfATruncatedList() {
        let labels = MarkAllReadLabels(count: 500, participatingOnly: false, isTruncated: true)
        #expect(labels.confirmation == "Mark all as read?")
        #expect(!labels.confirmation.contains("500 as read"))
        for text in [labels.help(confirming: false), labels.accessibilityLabel(confirming: true)] {
            #expect(text.contains("older unread threads that are not shown here"))
        }
        #expect(labels.accessibilityLabel(confirming: true).hasPrefix("Confirm marking all as read. "))
    }

    @Test func keepsTheParticipatingOnlyLabels() {
        let labels = MarkAllReadLabels(count: 2, participatingOnly: true, isTruncated: false)
        #expect(labels.confirmation == "Mark all as read?")
        let help = labels.help(confirming: false)
        #expect(help.hasPrefix("Mark all as read. "))
        #expect(help.contains("not participating in"))
        #expect(!help.contains("older unread"))
    }

    @Test func mentionsBothReasons() {
        let labels = MarkAllReadLabels(count: 500, participatingOnly: true, isTruncated: true)
        let help = labels.help(confirming: true)
        #expect(help.contains("not participating in"))
        #expect(help.contains("older unread threads"))
    }
}
