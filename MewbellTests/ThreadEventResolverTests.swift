import Foundation
import Testing

@testable import Mewbell

/// Timeline の項目の JSON を作る（`cli/cli` と `yshrsmz/since-android` で確かめた形）。
enum TimelineJSON {
    static func event(_ name: String, at time: String, actor: String? = "alice") -> String {
        let actorJSON = actor.map { #"{"login": "\#($0)"}"# } ?? "null"
        return #"{"event": "\#(name)", "created_at": "\#(time)", "actor": \#(actorJSON), "body": "secret text"}"#
    }

    static func commented(at time: String, by login: String) -> String {
        #"{"event": "commented", "created_at": "\#(time)", "actor": {"login": "\#(login)"}, "user": {"login": "\#(login)"}, "body": "hello"}"#
    }

    static func reviewed(_ state: String, at time: String, by login: String) -> String {
        #"{"event": "reviewed", "submitted_at": "\#(time)", "state": "\#(state)", "user": {"login": "\#(login)"}, "body": "ok"}"#
    }

    static func committed(at time: String) -> String {
        #"{"event": "committed", "sha": "abc", "author": {"name": "Alice A", "date": "\#(time)"}, "committer": {"name": "Alice A", "date": "\#(time)"}}"#
    }

    static func page(_ items: [String]) -> Data {
        Data("[\(items.joined(separator: ","))]".utf8)
    }

    static func issue(
        createdAt: String, user: String? = "author", state: String = "open", stateReason: String? = nil,
        draft: Bool? = nil, pullRequest: Bool = false, mergedAt: String? = nil
    ) -> Data {
        var fields = [
            #""number": 7"#, #""created_at": "\#(createdAt)""#, #""state": "\#(state)""#, #""body": "secret""#,
            #""user": \#(user.map { #"{"login": "\#($0)"}"# } ?? "null")"#,
            #""state_reason": \#(stateReason.map { "\"\($0)\"" } ?? "null")"#,
        ]
        if let draft { fields.append(#""draft": \#(draft)"#) }
        if pullRequest { fields.append(#""pull_request": {"merged_at": \#(mergedAt.map { "\"\($0)\"" } ?? "null")}"#) }
        return Data("{\(fields.joined(separator: ","))}".utf8)
    }
}

struct ThreadEventResolverTests {
    private func resolve(created: String, updated: String, _ items: [String], user: String? = "author")
        throws -> ThreadEvent?
    {
        let issue = try #require(IssueSummary.decode(from: TimelineJSON.issue(createdAt: created, user: user)))
        let timeline = try #require(TimelineItem.decodePage(from: TimelineJSON.page(items)))
        return ThreadEventResolver.event(
            issue: issue, timeline: timeline, updatedAt: try #require(ThreadEventResolver.date(updated)))
    }

    @Test func comment() throws {
        let event = try resolve(
            created: "2026-10-08T10:00:00Z", updated: "2026-10-08T12:00:30Z",
            [
                TimelineJSON.event("labeled", at: "2026-10-08T11:30:00Z"),
                TimelineJSON.commented(at: "2026-10-08T12:00:00Z", by: "bob"),
            ])
        #expect(event == ThreadEvent(kind: .commented, actor: "bob"))
    }

    @Test func merge() throws {
        let event = try resolve(
            created: "2026-10-09T14:03:29Z", updated: "2026-10-09T14:47:45Z",
            [
                TimelineJSON.reviewed("approved", at: "2026-10-09T14:33:25Z", by: "williammartin"),
                TimelineJSON.event("merged", at: "2026-10-09T14:47:45Z", actor: "williammartin"),
                TimelineJSON.event("closed", at: "2026-10-09T14:47:45Z", actor: "williammartin"),
                TimelineJSON.event("head_ref_deleted", at: "2026-10-09T14:47:47Z", actor: "williammartin"),
            ])
        #expect(event == ThreadEvent(kind: .merged, actor: "williammartin"))
    }

    @Test func picksTheClosestCandidate() throws {
        let event = try resolve(
            created: "2026-10-11T16:12:06Z", updated: "2026-10-11T16:18:08Z",
            [
                TimelineJSON.committed(at: "2026-10-11T16:11:56Z"),
                TimelineJSON.commented(at: "2026-10-11T16:17:15Z", by: "github-actions[bot]"),
                TimelineJSON.event("merged", at: "2026-10-11T16:17:32Z", actor: "yshrsmz"),
                TimelineJSON.event("closed", at: "2026-10-11T16:17:32Z", actor: "yshrsmz"),
                TimelineJSON.event("head_ref_deleted", at: "2026-10-11T16:17:34Z", actor: "yshrsmz"),
                TimelineJSON.commented(at: "2026-10-11T16:17:46Z", by: "sincetimer-android-app[bot]"),
            ])
        #expect(event == ThreadEvent(kind: .commented, actor: "sincetimer-android-app[bot]"))
    }

    @Test func doesNotUseFarCandidates() throws {
        let event = try resolve(
            created: "2026-10-08T09:00:00Z", updated: "2026-10-08T12:00:00Z",
            [
                TimelineJSON.commented(at: "2026-10-08T10:00:00Z", by: "bob"),
                TimelineJSON.committed(at: "2026-10-08T11:00:00Z"),
            ])
        #expect(event == nil)
    }

    @Test func doesNotUseLaterEvents() throws {
        let event = try resolve(
            created: "2026-10-08T09:00:00Z", updated: "2026-10-08T12:00:00Z",
            [
                TimelineJSON.event("closed", at: "2026-10-08T11:59:00Z", actor: "alice"),
                TimelineJSON.commented(at: "2026-10-08T15:00:00Z", by: "bob"),
            ])
        #expect(event == ThreadEvent(kind: .closed, actor: "alice"))
    }

    @Test func openedPullRequest() throws {
        let event = try resolve(
            created: "2026-10-09T19:39:42Z", updated: "2026-10-09T19:39:42Z",
            [
                TimelineJSON.committed(at: "2026-10-08T22:12:48Z"),
                TimelineJSON.event("review_requested", at: "2026-10-09T19:39:43Z", actor: "BagToad"),
                TimelineJSON.event("labeled", at: "2026-10-09T19:39:43Z", actor: "BagToad"),
            ], user: "BagToad")
        #expect(event == ThreadEvent(kind: .opened, actor: "BagToad"))
    }

    @Test func onlyIgnoredEvents() throws {
        let event = try resolve(
            created: "2026-10-08T10:00:00Z", updated: "2026-10-08T12:00:00Z",
            [
                TimelineJSON.event("labeled", at: "2026-10-08T12:00:00Z"),
                TimelineJSON.event("cross-referenced", at: "2026-10-08T12:00:00Z"),
                TimelineJSON.event("some_new_event", at: "2026-10-08T12:00:00Z"),
            ])
        #expect(event == nil)
    }

    @Test func botActor() throws {
        let event = try resolve(
            created: "2026-10-08T10:00:00Z", updated: "2026-10-08T12:00:00Z",
            [TimelineJSON.commented(at: "2026-10-08T11:59:40Z", by: "dependabot[bot]")])
        #expect(event == ThreadEvent(kind: .commented, actor: "dependabot[bot]"))
    }

    @Test func nullOrInvalidActor() throws {
        let null = try resolve(
            created: "2026-10-08T10:00:00Z", updated: "2026-10-08T12:00:00Z",
            [TimelineJSON.event("closed", at: "2026-10-08T11:59:40Z", actor: nil)])
        #expect(null == ThreadEvent(kind: .closed, actor: nil))
        #expect(null?.actor == nil)
        let invalid = try resolve(
            created: "2026-10-08T10:00:00Z", updated: "2026-10-08T12:00:00Z",
            [TimelineJSON.event("closed", at: "2026-10-08T11:59:40Z", actor: "-evil")])
        #expect(invalid?.actor == nil)
    }

    @Test(arguments: [
        ("approved", ThreadEvent.Kind.approved), ("changes_requested", .changesRequested), ("commented", .reviewed),
    ])
    func reviews(_ state: String, _ kind: ThreadEvent.Kind) throws {
        let event = try resolve(
            created: "2026-10-08T10:00:00Z", updated: "2026-10-08T12:00:00Z",
            [TimelineJSON.reviewed(state, at: "2026-10-08T11:59:40Z", by: "bob")])
        #expect(event == ThreadEvent(kind: kind, actor: "bob"))
    }

    @Test(arguments: [
        ("reopened", ThreadEvent.Kind.reopened), ("ready_for_review", .readyForReview),
        ("convert_to_draft", .convertedToDraft), ("review_requested", .reviewRequested), ("assigned", .assigned),
        ("head_ref_force_pushed", .forcePushed),
    ])
    func actorEvents(_ name: String, _ kind: ThreadEvent.Kind) throws {
        let event = try resolve(
            created: "2026-10-08T10:00:00Z", updated: "2026-10-08T12:00:00Z",
            [TimelineJSON.event(name, at: "2026-10-08T11:59:40Z", actor: "carol")])
        #expect(event == ThreadEvent(kind: kind, actor: "carol"))
    }

    @Test func commitPushedRightAway() throws {
        let event = try resolve(
            created: "2026-10-08T10:00:00Z", updated: "2026-10-08T12:00:20Z",
            [
                TimelineJSON.commented(at: "2026-10-08T11:00:00Z", by: "bob"),
                TimelineJSON.committed(at: "2026-10-08T12:00:00Z"),
            ])
        #expect(event == ThreadEvent(kind: .pushedCommits, actor: nil))
    }

    @Test func closedWithoutMergeStaysClosed() throws {
        let event = try resolve(
            created: "2026-10-08T10:00:00Z", updated: "2026-10-08T12:00:00Z",
            [
                TimelineJSON.event("merged", at: "2026-10-08T11:00:00Z", actor: "bob"),
                TimelineJSON.event("closed", at: "2026-10-08T11:59:50Z", actor: "alice"),
            ])
        #expect(event == ThreadEvent(kind: .closed, actor: "alice"))
    }

    @Test func doesNotKeepCommentBodies() throws {
        let items = try #require(
            TimelineItem.decodePage(
                from: TimelineJSON.page([TimelineJSON.commented(at: "2026-10-08T12:00:00Z", by: "bob")])))
        #expect(!String(describing: items).contains("hello"))
    }

    @Test func skipsMalformedItemsAndRejectsNonArrays() throws {
        let items = try #require(
            TimelineItem.decodePage(from: Data(#"[{"event": 1}, {"event": "commented"}, 3]"#.utf8)))
        #expect(items.count == 1)
        #expect(TimelineItem.decodePage(from: Data(#"{"message": "x"}"#.utf8)) == nil)
    }
}

struct SubjectStateTests {
    private func state(_ data: Data) throws -> SubjectState? {
        try #require(IssueSummary.decode(from: data)).subjectState
    }

    @Test func mergedPullRequest() throws {
        #expect(
            try state(
                TimelineJSON.issue(
                    createdAt: "2026-10-09T14:03:29Z", state: "closed", draft: false, pullRequest: true,
                    mergedAt: "2026-10-09T14:47:45Z")) == .merged)
    }

    @Test func pullRequests() throws {
        let created = "2026-10-09T14:03:29Z"
        #expect(try state(TimelineJSON.issue(createdAt: created, state: "closed", pullRequest: true)) == .closed)
        #expect(try state(TimelineJSON.issue(createdAt: created, draft: true, pullRequest: true)) == .draft)
        #expect(try state(TimelineJSON.issue(createdAt: created, draft: false, pullRequest: true)) == .open)
        #expect(try state(TimelineJSON.issue(createdAt: created, pullRequest: true)) == .open)
    }

    @Test func issues() throws {
        let created = "2026-10-09T14:03:29Z"
        #expect(try state(TimelineJSON.issue(createdAt: created)) == .open)
        #expect(
            try state(TimelineJSON.issue(createdAt: created, state: "closed", stateReason: "not_planned"))
                == .closedNotPlanned)
        #expect(
            try state(TimelineJSON.issue(createdAt: created, state: "closed", stateReason: "completed"))
                == .closedCompleted)
        #expect(try state(TimelineJSON.issue(createdAt: created, state: "closed")) == .closedCompleted)
        #expect(try state(TimelineJSON.issue(createdAt: created, state: "locked")) == nil)
    }

    @Test func rejectsAMalformedIssue() {
        #expect(IssueSummary.decode(from: Data(#"{"state": "open"}"#.utf8)) == nil)
    }
}
