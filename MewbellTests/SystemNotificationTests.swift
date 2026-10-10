import AppKit
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

/// `SystemNotifier` の、通知センターへの操作（新着の判定は `NotificationStoreNewThreadsTests`）。
@MainActor
struct SystemNotifierTests {
    private let center = FakeUserNotificationCenter()
    private let notifier: SystemNotifier

    init() {
        notifier = SystemNotifier(center: center)
    }

    @Test func postsNothingForTheBaselineAndClearsStaleNotifications() async {
        center.delivered.value = ["github.com/alice/1", "github.com/alice/9", "github.com/bob/9"]
        notifier.baselineSet(for: alice, keeping: ["1", "2"])
        await notifier.waitForPendingWork()
        #expect(center.added.value.isEmpty)
        #expect(center.delivered.value == ["github.com/alice/1", "github.com/bob/9"])
    }

    @Test func postsNewThreadsAndRetractsGoneOnes() async throws {
        center.delivered.value = ["github.com/alice/1"]
        notifier.threadsChanged(for: alice, posted: [try thread("3")], retracted: ["1"])
        await notifier.waitForPendingWork()
        #expect(center.added.value.map(\.identifier) == ["github.com/alice/3"])
        #expect(center.delivered.value == ["github.com/alice/3"])
    }

    @Test func clearsTheAccountForAnEmptyBaseline() async {
        // 前回の実行の通知を掃除する
        center.delivered.value = ["github.com/alice/9", "github.com/bob/9"]
        notifier.baselineSet(for: alice, keeping: [])
        await notifier.waitForPendingWork()
        #expect(center.delivered.value == ["github.com/bob/9"])
    }

    @Test func retractsAThreadMarkedRead() async {
        center.delivered.value = ["github.com/alice/1", "github.com/alice/2"]
        notifier.threadRemoved("1", for: alice)
        await notifier.waitForPendingWork()
        #expect(center.delivered.value == ["github.com/alice/2"])
    }

    @Test func retractsOnlyTheAccountMarkedAllRead() async {
        center.delivered.value = ["github.com/alice/1", "github.com/alice/2", "github.com/bob/3"]
        notifier.threadsChanged(for: alice, posted: [], retracted: ["1", "2"])
        await notifier.waitForPendingWork()
        #expect(center.delivered.value == ["github.com/bob/3"])
        #expect(center.added.value.isEmpty)
    }

    @Test func retractsTheAccountWhenItStopsOrIsRemoved() async {
        center.delivered.value = [
            "github.com/alice/1", "github.com/alice/2", "github.com/bob/1", "github.com/alice2/1",
        ]
        notifier.accountRemoved(alice)
        await notifier.waitForPendingWork()
        #expect(center.delivered.value == ["github.com/bob/1", "github.com/alice2/1"])
        notifier.accountRemoved(bob)
        await notifier.waitForPendingWork()
        #expect(center.delivered.value == ["github.com/alice2/1"])
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
struct MenuBarIconTests {
    @Test func isATemplateOnlyWithoutUnread() {
        #expect(MenuBarIcon.image(badge: nil).isTemplate)
        #expect(!MenuBarIcon.image(badge: "1").isTemplate)
    }

    @Test func describesTheImageForVoiceOver() {
        #expect(MenuBarIcon.image(badge: nil).accessibilityDescription == "Mewbell")
        #expect(MenuBarIcon.image(badge: "5").accessibilityDescription == "Mewbell, 5 unread")
    }

    @Test func widensWithTheBadge() {
        let cat = MenuBarIcon.image(badge: nil).size.width
        let one = MenuBarIcon.image(badge: "1").size.width
        let many = MenuBarIcon.image(badge: "99+").size.width
        #expect(cat < one)
        #expect(one < many)
    }

    /// 猫（左）は緑で、件数（右）は外観に合った文字の色で描かれる。
    @Test(arguments: [(NSAppearance.Name.aqua, false), (.darkAqua, true)])
    func drawsAGreenCatAndALabelColoredBadge(_ appearance: NSAppearance.Name, _ isDark: Bool) throws {
        let image = MenuBarIcon.image(badge: "5")
        let bitmap = try render(image, in: try #require(NSAppearance(named: appearance)))
        // 猫だけの画像の幅で、猫と件数の列を分ける（ビットマップは 2 倍で描く）
        let catColumns = Int(MenuBarIcon.image(badge: nil).size.width * 2)
        let cat = pixels(of: bitmap, columns: 0..<catColumns)
        let badge = pixels(of: bitmap, columns: catColumns..<bitmap.pixelsWide)
        #expect(cat.contains { $0.greenComponent > 0.5 && $0.greenComponent > $0.redComponent + 0.2 })
        #expect(
            badge.contains { color in
                let brightness = (color.redComponent + color.greenComponent + color.blueComponent) / 3
                return isDark ? brightness > 0.7 : brightness < 0.3
            })
    }

    private func render(_ image: NSImage, in appearance: NSAppearance) throws -> NSBitmapImageRep {
        let bitmap = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(image.size.width * 2), pixelsHigh: Int(image.size.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = image.size
        appearance.performAsCurrentDrawingAppearance {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            image.draw(in: NSRect(origin: .zero, size: image.size))
            NSGraphicsContext.restoreGraphicsState()
        }
        return bitmap
    }

    /// 指定した列の、ほぼ不透明な画素。
    private func pixels(of bitmap: NSBitmapImageRep, columns: Range<Int>) -> [NSColor] {
        columns.flatMap { column in
            (0..<bitmap.pixelsHigh).compactMap { row in
                bitmap.colorAt(x: column, y: row).flatMap { $0.alphaComponent > 0.8 ? $0 : nil }
            }
        }
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
