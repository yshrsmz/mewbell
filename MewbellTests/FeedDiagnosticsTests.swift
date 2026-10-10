import Foundation
import Testing

@testable import Mewbell

struct FeedDiagnosticsTests {
    @Test(arguments: [
        (FetchFailure.rejectedURL, FailureKind.rejectedURL),
        (.redirect, .redirect),
        (.bodyTooLarge, .bodyTooLarge),
        (.network(code: URLError.Code.timedOut.rawValue), .network),
        (.unexpectedStatus(502), .httpStatus(502)),
        (.malformedBody, .malformedBody),
        (.noToken, .noToken),
    ])
    func classifiesFetchFailures(_ failure: FetchFailure, _ expected: FailureKind) {
        #expect(FailureKind(failure) == expected)
        #expect(FailureKind(NotificationsFetchResult.failed(failure)) == expected)
        #expect(FailureKind(ThreadActionResult.failed(failure)) == expected)
    }

    @Test func classifiesFetchResults() {
        #expect(FailureKind(NotificationsFetchResult.notModified(pollInterval: nil)) == nil)
        #expect(
            FailureKind(
                NotificationsFetchResult.updated(
                    threads: [], lastModified: nil, pollInterval: nil, scopes: OAuthScopes(header: nil),
                    truncated: false)) == nil)
        #expect(FailureKind(NotificationsFetchResult.unauthorized) == .unauthorized)
        #expect(FailureKind(NotificationsFetchResult.rateLimited(retryAt: Date())) == .rateLimited)
        #expect(FailureKind(NotificationsFetchResult.forbidden(scopes: OAuthScopes(header: nil))) == .httpStatus(403))
        #expect(FailureKind(NotificationsFetchResult.invalidRequest) == .httpStatus(422))
    }

    @Test func classifiesActionResults() {
        #expect(FailureKind(ThreadActionResult.succeeded) == nil)
        #expect(FailureKind(ThreadActionResult.unauthorized) == .unauthorized)
        #expect(FailureKind(ThreadActionResult.rateLimited) == .rateLimited)
    }

    @Test func derivesThePollInterval() {
        #expect(PollIntervalInfo(pollInterval: 120) == PollIntervalInfo(seconds: 120, fromHeader: true))
        #expect(PollIntervalInfo(pollInterval: 60) == PollIntervalInfo(seconds: 60, fromHeader: true))
        #expect(PollIntervalInfo(pollInterval: nil) == PollIntervalInfo(seconds: 60, fromHeader: false))
        #expect(PollIntervalInfo(pollInterval: 30) == PollIntervalInfo(seconds: 60, fromHeader: false))
    }

    @Test func newFieldsDefaultToEmpty() {
        let state = FeedState(phase: .loading, threads: [])
        #expect(!state.isTruncated)
        #expect(state.actionFailure == nil)
        #expect(state.diagnostics == FeedDiagnostics())
        #expect(FeedState.loading == state)
    }
}
