import AppKit
import Testing

@testable import Mewbell

@MainActor
struct StatusItemMenuTests {
    @Test func listsTheItemsInOrder() {
        let menu = StatusItemMenu(openURL: { _ in }).menu
        let items = menu.items.map { $0.isSeparatorItem ? "-" : "\($0.title)|\($0.keyEquivalent)" }
        #expect(items == ["About Mewbell|", "-", "Settings…|,", "Mewbell Releases|", "-", "Quit Mewbell|q"])
    }

    @Test func quitGoesThroughTheApplication() {
        let quit = StatusItemMenu(openURL: { _ in }).menu.items.last
        #expect(quit?.action == #selector(NSApplication.terminate(_:)))
        #expect(quit?.target == nil)
    }

    @Test func opensTheFixedReleasesPage() {
        var opened: [URL] = []
        // 項目の target は弱参照なので、StatusItemMenu を持ち続ける
        let statusMenu = StatusItemMenu(openURL: { opened.append($0) })
        let menu = statusMenu.menu
        menu.performActionForItem(at: menu.indexOfItem(withTitle: "Mewbell Releases"))
        #expect(opened.map(\.absoluteString) == ["https://github.com/yshrsmz/mewbell/releases"])
        #expect(opened.first?.scheme == "https")
    }

    @Test func opensSettingsThroughTheGivenAction() {
        var opens = 0
        let statusMenu = StatusItemMenu(openURL: { _ in })
        statusMenu.openSettings = { opens += 1 }
        let menu = statusMenu.menu
        menu.performActionForItem(at: menu.indexOfItem(withTitle: "Settings…"))
        #expect(opens == 1)
    }
}
