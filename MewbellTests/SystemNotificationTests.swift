import Foundation
import Testing

@testable import Mewbell

private let alice = AccountID(host: "github.com", user: "alice")
private let bob = AccountID(host: "github.com", user: "bob")

private func thread(
    _ id: String, updatedAt: TimeInterval = 0, repository: String = "octo/app", kind: SubjectKind = .issue,
    subjectURL: String? = nil, reason: String = "subscribed"
) throws -> NotificationThread {
    NotificationThread(
        id: id, reason: reason, updatedAt: Date(timeIntervalSince1970: updatedAt), title: "Thread \(id)", kind: kind,
        subjectURL: subjectURL.flatMap(URL.init(string:)),
        repository: try #require(RepositoryName(fullName: repository)))
}

struct NotificationTrackerTests {
    @Test func postsNothingForTheBaseline() throws {
        var tracker = NotificationTracker()
        tracker.baseline([try thread("1"), try thread("2")], for: alice)
        #expect(tracker.update([try thread("1"), try thread("2")], for: alice) == .init())
    }

    @Test func postsNewAndAdvancedThreadsOnly() throws {
        var tracker = NotificationTracker()
        tracker.baseline([try thread("1"), try thread("2")], for: alice)
        let changes = tracker.update([try thread("1", updatedAt: 10), try thread("2"), try thread("3")], for: alice)
        #expect(changes.post.map(\.id) == ["1", "3"])
        #expect(changes.retract.isEmpty)
        #expect(
            tracker.update([try thread("1", updatedAt: 10), try thread("2"), try thread("3")], for: alice) == .init())
    }

    @Test func retractsThreadsThatAreGoneAndDoesNotRepostThemUnchanged() throws {
        var tracker = NotificationTracker()
        tracker.baseline([try thread("1"), try thread("2")], for: alice)
        #expect(tracker.update([try thread("1")], for: alice).retract == ["2"])
        // 既読化に失敗して同じ updated_at で戻った
        #expect(tracker.update([try thread("1"), try thread("2")], for: alice) == .init())
        // 動きがあって戻った
        #expect(tracker.update([try thread("1"), try thread("2", updatedAt: 5)], for: alice).post.map(\.id) == ["2"])
    }

    @Test func startsOverAfterReset() throws {
        var tracker = NotificationTracker()
        tracker.baseline([try thread("1")], for: alice)
        tracker.reset(alice)
        // 基準が無いときの更新は基準になる
        #expect(tracker.update([try thread("1"), try thread("2")], for: alice) == .init())
        #expect(
            tracker.update([try thread("1"), try thread("2"), try thread("3")], for: alice).post.map(\.id) == ["3"])
    }

    @Test func keepsAccountsApart() throws {
        var tracker = NotificationTracker()
        tracker.baseline([try thread("1")], for: alice)
        tracker.baseline([], for: bob)
        let changes = tracker.update([try thread("1")], for: bob)
        #expect(changes.post.map(\.id) == ["1"])
        #expect(tracker.update([try thread("1")], for: alice) == .init())
    }
}

struct ThreadNotificationContentTests {
    @Test func describesTheThread() throws {
        let content = ThreadNotificationContent(
            thread: try thread(
                "123", kind: .pullRequest, subjectURL: "https://api.github.com/repos/octo/app/pulls/42",
                reason: "review_requested"),
            account: alice)
        #expect(content.identifier == "github.com/alice/123")
        #expect(content.title == "Thread 123")
        #expect(content.subtitle == "octo/app")
        #expect(content.body == "Review requested · alice@github.com")
        #expect(content.threadIdentifier == "github.com/alice")
        #expect(
            content.userInfo == [
                "host": "github.com", "user": "alice", "threadID": "123", "repository": "octo/app",
                "url": "https://github.com/octo/app/pull/42",
            ])
    }

    @Test func leaksNeitherTheTokenNorAPIURLs() throws {
        let content = ThreadNotificationContent(
            thread: try thread("7", subjectURL: "https://ghe.example.com/api/v3/repos/octo/app/issues/7"),
            account: AccountID(host: "ghe.example.com", user: "dave"))
        let texts =
            [content.identifier, content.title, content.subtitle, content.body, content.threadIdentifier]
            + content.userInfo.keys + content.userInfo.values
        for text in texts {
            #expect(!text.contains("test-token"))
            #expect(!text.contains("/api/v3"))
            #expect(!text.contains("api.github.com"))
        }
        #expect(content.userInfo["url"] == "https://ghe.example.com/octo/app/issues/7")
    }
}

struct ThreadOpenRequestTests {
    private let valid: [String: String] = [
        "host": "github.com", "user": "alice", "threadID": "123", "repository": "octo/app",
        "url": "https://github.com/octo/app/pull/42",
    ]

    private func request(_ changes: [String: String?]) -> ThreadOpenRequest? {
        var userInfo = valid
        for (key, value) in changes {
            userInfo[key] = value
        }
        return ThreadOpenRequest(userInfo: userInfo)
    }

    @Test func acceptsValidUserInfo() throws {
        let request = try #require(request([:]))
        #expect(request.account == alice)
        #expect(request.threadID == "123")
        #expect(request.url.absoluteString == "https://github.com/octo/app/pull/42")
    }

    @Test(arguments: [
        ["host": "evil example.com"], ["host": "-github.com"], ["host": nil], ["user": "-alice"],
        ["user": "alice/bob"], ["threadID": "../user"], ["threadID": "12a"], ["threadID": nil],
    ])
    func rejectsInvalidIdentifiers(_ changes: [String: String?]) {
        #expect(request(changes) == nil)
    }

    @Test(arguments: [
        "https://evil.example.com/octo/app/pull/42", "http://github.com/octo/app/pull/42",
        "https://github.com:8443/octo/app/pull/42", "https://user@github.com/octo/app/pull/42", "not a url",
    ])
    func replacesAnUnsafeURLWithTheRepositoryPage(_ url: String) throws {
        let request = try #require(request(["url": url]))
        #expect(request.url.absoluteString == "https://github.com/octo/app")
    }

    @Test func fallsBackToTheRepositoryPageWithoutAURL() throws {
        #expect(try #require(request(["url": nil])).url.absoluteString == "https://github.com/octo/app")
    }

    @Test(arguments: ["../../etc", "octo", "octo/app/extra"])
    func rejectsAnUnsafeURLWithAnInvalidRepository(_ repository: String) {
        #expect(request(["url": "https://evil.example.com/", "repository": repository]) == nil)
    }

    @Test func ignoresNonStringValues() {
        var userInfo: [AnyHashable: Any] = valid
        userInfo["threadID"] = 123
        #expect(ThreadOpenRequest(userInfo: userInfo) == nil)
    }
}

@MainActor
struct SystemNotifierTests {
    private let center = FakeUserNotificationCenter()
    private let notifier: SystemNotifier
    private let loaded = FeedPhase.loaded(updatedAt: Date(timeIntervalSince1970: 0))

    init() {
        notifier = SystemNotifier(center: center)
    }

    private func feed(_ threads: [NotificationThread]) -> FeedState {
        FeedState(phase: loaded, threads: threads)
    }

    @Test func postsNothingForTheFirstFetchAndClearsStaleNotifications() async throws {
        center.delivered.value = ["github.com/alice/1", "github.com/alice/9", "github.com/bob/9"]
        notifier.feedChanged(for: alice, from: .loading, to: feed([try thread("1"), try thread("2")]))
        await notifier.waitForPendingWork()
        #expect(center.added.value.isEmpty)
        #expect(center.delivered.value == ["github.com/alice/1", "github.com/bob/9"])
    }

    @Test func postsNewThreadsAndRetractsGoneOnes() async throws {
        let first = feed([try thread("1"), try thread("2")])
        notifier.feedChanged(for: alice, from: .loading, to: first)
        await notifier.waitForPendingWork()
        center.delivered.value = ["github.com/alice/1"]
        let second = feed([try thread("2"), try thread("3")])
        notifier.feedChanged(for: alice, from: first, to: second)
        await notifier.waitForPendingWork()
        #expect(center.added.value.map(\.identifier) == ["github.com/alice/3"])
        #expect(center.delivered.value == ["github.com/alice/3"])
        // 304 の後（スレッドが同じ）は何もしない
        notifier.feedChanged(
            for: alice, from: second, to: FeedState(phase: .loaded(updatedAt: .now), threads: second.threads))
        await notifier.waitForPendingWork()
        #expect(center.added.value.count == 1)
    }

    @Test func makesTheBaselineAfterAFailedFirstFetch() async throws {
        center.delivered.value = ["github.com/alice/9"]
        let retrying = FeedState(phase: .retrying(nextAttempt: .now, rateLimited: false), threads: [])
        notifier.feedChanged(for: alice, from: .loading, to: retrying)
        let first = feed([])
        notifier.feedChanged(for: alice, from: retrying, to: first)
        await notifier.waitForPendingWork()
        // 前回の実行の通知を掃除する
        #expect(center.delivered.value.isEmpty)
        notifier.feedChanged(for: alice, from: first, to: feed([try thread("1")]))
        await notifier.waitForPendingWork()
        #expect(center.added.value.map(\.identifier) == ["github.com/alice/1"])
    }

    @Test func retractsAThreadMarkedRead() async throws {
        notifier.feedChanged(for: alice, from: .loading, to: feed([try thread("1"), try thread("2")]))
        await notifier.waitForPendingWork()
        center.delivered.value = ["github.com/alice/1", "github.com/alice/2"]
        notifier.threadRead("1", for: alice)
        await notifier.waitForPendingWork()
        #expect(center.delivered.value == ["github.com/alice/2"])
    }

    @Test func doesNothingWhileRetrying() async throws {
        let first = feed([try thread("1")])
        notifier.feedChanged(for: alice, from: .loading, to: first)
        center.delivered.value = ["github.com/alice/1"]
        notifier.feedChanged(
            for: alice, from: first,
            to: FeedState(phase: .retrying(nextAttempt: .now, rateLimited: false), threads: first.threads))
        await notifier.waitForPendingWork()
        #expect(center.delivered.value == ["github.com/alice/1"])
        #expect(center.added.value.isEmpty)
    }

    @Test func retractsTheAccountWhenItStopsOrIsRemoved() async throws {
        center.delivered.value = [
            "github.com/alice/1", "github.com/alice/2", "github.com/bob/1", "github.com/alice2/1",
        ]
        notifier.feedChanged(for: alice, from: feed([]), to: FeedState(phase: .unauthorized, threads: []))
        await notifier.waitForPendingWork()
        #expect(center.delivered.value == ["github.com/bob/1", "github.com/alice2/1"])
        notifier.accountRemoved(bob)
        await notifier.waitForPendingWork()
        #expect(center.delivered.value == ["github.com/alice2/1"])
    }

    @Test func startsOverAfterStopping() async throws {
        notifier.feedChanged(for: alice, from: .loading, to: feed([try thread("1")]))
        notifier.feedChanged(for: alice, from: feed([]), to: FeedState(phase: .unauthorized, threads: []))
        // 再開の後の最初の取得は基準
        notifier.feedChanged(for: alice, from: .loading, to: feed([try thread("1"), try thread("2")]))
        await notifier.waitForPendingWork()
        #expect(center.added.value.isEmpty)
    }

    @Test func retainsOnlyListedAccounts() async {
        center.delivered.value = ["github.com/alice/1", "github.com/bob/1", "ghe.example.com/alice/1"]
        notifier.retainOnly([alice])
        await notifier.waitForPendingWork()
        #expect(center.delivered.value == ["github.com/alice/1"])
        notifier.retainOnly([])
        await notifier.waitForPendingWork()
        #expect(center.delivered.value.isEmpty)
    }
}

struct UnreadBadgeTests {
    @Test(arguments: [(0, String?.none), (-1, nil), (1, "1"), (99, "99"), (100, "99+"), (1_000, "99+")])
    func formats(_ count: Int, _ text: String?) {
        #expect(UnreadBadge.text(for: count) == text)
    }
}

@MainActor
struct NotificationPermissionTests {
    @Test func keepsTheRequestResultOverAStaleRefresh() async {
        let center = FakeUserNotificationCenter()
        center.status.value = .denied
        let permission = NotificationPermission(center: center)
        permission.request()
        // 求めている途中の読み直しは何もしない
        permission.refresh()
        await waitUntil { MainActor.assumeIsolated { permission.authorization != nil } }
        #expect(permission.authorization == .denied)
        #expect(permission.isDenied)
        center.status.value = .allowed
        permission.refresh()
        await waitUntil { MainActor.assumeIsolated { permission.authorization == .allowed } }
        #expect(!permission.isDenied)
    }
}
