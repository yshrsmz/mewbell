import Foundation
import Testing

@testable import Mewbell

struct FeedDiagnosticsTests {
    @Test(arguments: [
        (FetchFailure.unexpectedStatus(502), FailureKind.httpStatus(502)),
        (.network(code: URLError.Code.timedOut.rawValue), .network),
    ])
    func classifiesFetchFailures(_ failure: FetchFailure, _ expected: FailureKind) {
        #expect(FailureKind(failure) == expected)
        #expect(FailureKind(NotificationsFetchResult.failed(failure)) == expected)
        #expect(FailureKind(ThreadActionResult.failed(failure)) == expected)
    }

    /// ポーラーのテストで記録を確かめていない、取得の結果の分類。
    @Test func classifiesFetchResults() {
        #expect(FailureKind(NotificationsFetchResult.rateLimited(retryAt: Date())) == .rateLimited)
        #expect(FailureKind(NotificationsFetchResult.invalidRequest) == .httpStatus(422))
    }

    @Test func derivesThePollInterval() {
        #expect(PollIntervalInfo(pollInterval: 120) == PollIntervalInfo(seconds: 120, fromHeader: true))
        #expect(PollIntervalInfo(pollInterval: 60) == PollIntervalInfo(seconds: 60, fromHeader: true))
        #expect(PollIntervalInfo(pollInterval: nil) == PollIntervalInfo(seconds: 60, fromHeader: false))
        #expect(PollIntervalInfo(pollInterval: 30) == PollIntervalInfo(seconds: 60, fromHeader: false))
    }
}
