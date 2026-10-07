import Foundation
import Testing

@testable import Mewbell

struct SingleInstanceTests {
    private let earlier = Date(timeIntervalSince1970: 1_000)
    private let later = Date(timeIntervalSince1970: 2_000)

    @Test func keepsRunningWhenNoOtherInstance() {
        let current = SingleInstance.Instance(processIdentifier: 100, launchDate: later)
        #expect(!SingleInstance.shouldTerminate(current: current, others: []))
    }

    @Test func terminatesWhenAnotherInstanceLaunchedEarlier() {
        let current = SingleInstance.Instance(processIdentifier: 100, launchDate: later)
        let other = SingleInstance.Instance(processIdentifier: 200, launchDate: earlier)
        #expect(SingleInstance.shouldTerminate(current: current, others: [other]))
    }

    @Test func keepsRunningWhenAnotherInstanceLaunchedLater() {
        let current = SingleInstance.Instance(processIdentifier: 200, launchDate: earlier)
        let other = SingleInstance.Instance(processIdentifier: 100, launchDate: later)
        #expect(!SingleInstance.shouldTerminate(current: current, others: [other]))
    }

    @Test func breaksTiesByProcessIdentifier() {
        let lower = SingleInstance.Instance(processIdentifier: 100, launchDate: earlier)
        let higher = SingleInstance.Instance(processIdentifier: 200, launchDate: earlier)
        #expect(SingleInstance.shouldTerminate(current: higher, others: [lower]))
        #expect(!SingleInstance.shouldTerminate(current: lower, others: [higher]))
    }

    @Test func fallsBackToProcessIdentifierWhenLaunchDateIsUnknown() {
        let current = SingleInstance.Instance(processIdentifier: 200, launchDate: nil)
        let other = SingleInstance.Instance(processIdentifier: 100, launchDate: later)
        #expect(SingleInstance.shouldTerminate(current: current, others: [other]))
    }

    @Test func ignoresItself() {
        let current = SingleInstance.Instance(processIdentifier: 100, launchDate: later)
        #expect(!SingleInstance.shouldTerminate(current: current, others: [current]))
    }
}
