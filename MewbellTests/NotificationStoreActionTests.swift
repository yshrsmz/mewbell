import Foundation
import Testing

@testable import Mewbell

/// `NotificationStore` の、開かずに既読・Done・すべて既読・すべて Done のテスト。
@MainActor
struct NotificationStoreActionTests {
    private let transport = FakeHTTPTransport { request in
        switch request.httpMethod {
        case "PATCH": HTTPResponse(statusCode: 205)
        case "DELETE": HTTPResponse(statusCode: 204)
        case "PUT": HTTPResponse(statusCode: 205)
        default: PollerFixture.ok(1...3)
        }
    }
    private let tokens = FakeTokenProvider()
    private let sleeper = ManualSleeper()
    private let opened = LockedValue<[URL]>([])
    private let center = FakeUserNotificationCenter()

    private let alice = AccountID(host: "github.com", user: "alice")
    private let bob = AccountID(host: "github.com", user: "bob")

    private func makeStore(notifier: (any ThreadNotifying)?) -> NotificationStore {
        let client = GitHubAPIClient(transport: transport)
        return NotificationStore(
            makePoller: { [tokens, sleeper] account, endpoints, _, _, _, onUpdate in
                AccountPoller(
                    accountID: account.id, endpoints: endpoints, client: client, tokens: tokens,
                    sleep: sleeper.sleep, onUpdate: onUpdate)
            }, notifier: notifier, openURL: { [opened] url in opened.withLock { $0.append(url) } })
    }

    private nonisolated func urls(_ method: String) -> [String] {
        transport.requests.filter { $0.httpMethod == method }.compactMap { $0.url?.absoluteString }
    }

    /// alice と bob がそれぞれ 3 件を取得し終えた store。
    private func loadedStore(notifier: (any ThreadNotifying)? = nil) async -> NotificationStore {
        tokens.set("test-token-alice", for: alice)
        tokens.set("test-token-bob", for: bob)
        let store = makeStore(notifier: notifier)
        store.sync(
            with: .accounts([
                AccountStatus(account: Account(id: alice, isActive: true), tokenState: .ready),
                AccountStatus(account: Account(id: bob, isActive: false), tokenState: .ready),
            ]))
        await sleeper.waitForSleeps(2)
        await waitUntil {
            MainActor.assumeIsolated { store.feeds[alice]?.threads.count == 3 && store.feeds[bob]?.threads.count == 3 }
        }
        return store
    }

    @Test func marksAThreadDoneWithoutOpeningIt() async throws {
        let notifier = SystemNotifier(center: center)
        let store = await loadedStore(notifier: notifier)
        await notifier.waitForPendingWork()
        center.delivered.value = ["github.com/alice/2"]
        let thread = try #require(store.feeds[alice]?.threads.first { $0.id == "2" })
        store.markDone(thread, in: alice)
        #expect(store.feeds[alice]?.threads.map(\.id) == ["1", "3"])
        #expect(store.unreadCount == 5)
        #expect(opened.value.isEmpty)
        await waitUntil { self.urls("DELETE").count == 1 }
        #expect(urls("DELETE") == ["https://api.github.com/notifications/threads/2"])
        #expect(urls("PATCH").isEmpty)
        await notifier.waitForPendingWork()
        #expect(center.delivered.value.isEmpty)
        store.stopAll()
    }

    @Test func marksTheThreadsOfARepositoryGroupDone() async throws {
        // 1 と 2 は octo/app、3 は octo/lib
        let page = [("1", "octo/app"), ("2", "octo/app"), ("3", "octo/lib")]
            .map { FakeHTTPTransport.threadJSON(id: $0.0, repository: $0.1) }
        transport.setHandler { request in
            switch request.httpMethod {
            case "DELETE": HTTPResponse(statusCode: 204)
            default: PollerFixture.ok(body: Data("[\(page.joined(separator: ","))]".utf8))
            }
        }
        let notifier = SystemNotifier(center: center)
        let store = await loadedStore(notifier: notifier)
        await notifier.waitForPendingWork()
        center.delivered.value = ["github.com/alice/1", "github.com/alice/2"]
        let group = try #require(store.repositories[alice]?.first { $0.repository.description == "octo/app" })
        store.markDone(group, in: alice)
        #expect(store.feeds[alice]?.threads.map(\.id) == ["3"])
        #expect(store.feeds[bob]?.threads.count == 3)
        #expect(opened.value.isEmpty)
        await waitUntil { self.urls("DELETE").count == 2 }
        #expect(
            Set(urls("DELETE")) == [
                "https://api.github.com/notifications/threads/1", "https://api.github.com/notifications/threads/2",
            ])
        await notifier.waitForPendingWork()
        #expect(center.delivered.value.isEmpty)
        store.stopAll()
    }

    @Test func marksAllThreadsOfOneAccountDoneNewestFirst() async {
        // 一覧の並びは新しい順でなくても、Done は更新日時が新しい順に 1 件ずつ送る
        let page = [("1", "12:00"), ("2", "12:30"), ("3", "11:00")]
            .map { FakeHTTPTransport.threadJSON(id: $0.0, updatedAt: "2026-10-08T\($0.1):00Z") }
        transport.setHandler { request in
            switch request.httpMethod {
            case "DELETE": HTTPResponse(statusCode: 204)
            default: PollerFixture.ok(body: Data("[\(page.joined(separator: ","))]".utf8))
            }
        }
        let notifier = SystemNotifier(center: center)
        let store = await loadedStore(notifier: notifier)
        await notifier.waitForPendingWork()
        center.delivered.value = ["github.com/alice/1", "github.com/alice/2", "github.com/bob/3"]
        store.markAllDone(in: alice)
        #expect(store.feeds[alice]?.threads.isEmpty == true)
        #expect(store.feeds[bob]?.threads.count == 3)
        #expect(opened.value.isEmpty)
        await waitUntil { self.urls("DELETE").count == 3 }
        #expect(
            urls("DELETE") == ["2", "1", "3"].map { "https://api.github.com/notifications/threads/\($0)" })
        #expect(urls("PUT").isEmpty)
        // alice の通知だけが取り下がる
        await notifier.waitForPendingWork()
        #expect(center.delivered.value == ["github.com/bob/3"])
        store.stopAll()
    }

    @Test func ignoresMarkAllDoneWithAnEmptyList() async {
        transport.setHandler { request in
            switch request.httpMethod {
            case "DELETE": HTTPResponse(statusCode: 204)
            default: PollerFixture.ok(body: Data("[]".utf8))
            }
        }
        tokens.set("test-token-alice", for: alice)
        let store = makeStore(notifier: nil)
        store.sync(with: .accounts([AccountStatus(account: Account(id: alice, isActive: true), tokenState: .ready)]))
        await sleeper.waitForSleeps(1)
        await waitUntil { MainActor.assumeIsolated { store.feeds[alice]?.phase.showsThreads == true } }
        store.markAllDone(in: alice)
        #expect(store.feeds[alice]?.threads.isEmpty == true)
        #expect(urls("DELETE").isEmpty)
        store.stopAll()
    }

    @Test func marksAThreadReadWithoutOpeningIt() async throws {
        let store = await loadedStore()
        let thread = try #require(store.feeds[alice]?.threads.first { $0.id == "2" })
        store.markRead(thread, in: alice)
        #expect(store.feeds[alice]?.threads.map(\.id) == ["1", "3"])
        #expect(opened.value.isEmpty)
        await waitUntil { self.urls("PATCH").count == 1 }
        #expect(urls("PATCH") == ["https://api.github.com/notifications/threads/2"])
        #expect(urls("DELETE").isEmpty)
        store.stopAll()
    }

    @Test func ignoresDoneWithoutAPoller() throws {
        let thread = try Self.thread()
        let store = NotificationStore(
            makePoller: nil, openURL: { _ in },
            feeds: [alice: FeedState(phase: .loaded(updatedAt: .now), threads: [thread])])
        store.markDone(thread, in: alice)
        #expect(store.feeds[alice]?.threads.map(\.id) == ["1"])
    }

    @Test func marksAllThreadsOfOneAccountRead() async {
        let notifier = SystemNotifier(center: center)
        let store = await loadedStore(notifier: notifier)
        await notifier.waitForPendingWork()
        center.delivered.value = ["github.com/alice/1", "github.com/alice/2", "github.com/bob/3"]
        #expect(store.feeds[alice]?.canMarkAllRead == true)
        store.markAllRead(in: alice)
        await waitUntil { MainActor.assumeIsolated { store.feeds[alice]?.threads.isEmpty == true } }
        #expect(store.feeds[alice]?.threads.isEmpty == true)
        #expect(store.feeds[bob]?.threads.count == 3)
        #expect(store.unreadCount == 3)
        #expect(store.feeds[alice]?.canMarkAllRead != true)
        // 一覧から外した後に PUT を送るので、届くまで待つ
        await waitUntil { self.urls("PUT").count == 1 }
        #expect(urls("PUT") == ["https://api.github.com/notifications"])
        // alice の通知だけが取り下がる
        await notifier.waitForPendingWork()
        #expect(center.delivered.value == ["github.com/bob/3"])
        store.stopAll()
    }

    private static func thread() throws -> NotificationThread {
        NotificationThread(
            id: "1", reason: "subscribed", updatedAt: .now, title: "Thread", kind: .issue, subjectURL: nil,
            repository: try #require(RepositoryName(owner: "octo", name: "app")), detailsSubject: nil)
    }

    /// 取得し終えていて、スレッドがあるときだけ、すべて既読にできる。
    @Test(arguments: [
        (FeedPhase.loaded(updatedAt: .now), true, true),
        (.loaded(updatedAt: .now), false, false),
        (.retrying(nextAttempt: .now, rateLimited: false), true, false),
    ])
    func canMarkAllReadOnlyWhenLoadedWithThreads(_ phase: FeedPhase, _ hasThreads: Bool, _ expected: Bool) throws {
        let feed = FeedState(phase: phase, threads: hasThreads ? [try Self.thread()] : [])
        #expect(feed.canMarkAllRead == expected)
    }
}
