import AppKit

/// メニューバーのアイコンの右クリック（Control+クリック、VoiceOver の「メニューを表示」）で出すメニュー。
/// `MenuBarExtra` には右クリックの API が無いので、`MenuBarExtra` が作ったステータスアイテムのボタンを探し、
/// 右ボタンのジェスチャー認識と `menu` を付ける（ローカルのイベントモニターは、Apple がステータスアイテムには勧めていない）。
@MainActor
final class StatusItemMenu: NSObject {
    /// Releases の項目で開くページ。固定の URL だけを開く
    private static let releasesURL = URL(string: "https://github.com/yshrsmz/mewbell/releases")

    private let openURL: (URL) -> Void
    /// 設定ウィンドウを開く。SwiftUI の `openSettings` はシーンの中でしか読めないので、`MenuBarLabel` から受け取る
    var openSettings: (() -> Void)?
    /// ジェスチャー認識と `menu` を付けたボタン（同じボタンに 2 つ目を付けないため）
    private weak var attachedButton: NSStatusBarButton?
    private(set) lazy var menu = makeMenu()

    init(openURL: @escaping (URL) -> Void) {
        self.openURL = openURL
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("About Mewbell", action: #selector(showAbout)))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(item("Mewbell Releases", action: #selector(openReleases)))
        menu.addItem(.separator())
        // target を付けずに NSApp に送り、`applicationShouldTerminate` の後片付けを通す
        menu.addItem(
            NSMenuItem(title: "Quit Mewbell", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    /// `MenuBarExtra` のステータスアイテムのボタンを探し、まだ付けていなければジェスチャー認識と `menu` を付ける。
    /// ボタンは `MenuBarExtra` がステータスアイテムを作った後にしか無いので、メニューバーのラベルが表示されたときに呼ぶ。
    /// 見つからなければ何もしない（右クリックはポップオーバーを開く `MenuBarExtra` の動きのままになる）。
    func attachToStatusItem() {
        guard let button = Self.findStatusBarButton(), button !== attachedButton else { return }
        let recognizer = NSClickGestureRecognizer(target: self, action: #selector(rightClicked(_:)))
        // 右ボタン。Control+クリックはシステムが右クリックに変えて届ける
        recognizer.buttonMask = 0x2
        button.addGestureRecognizer(recognizer)
        // VoiceOver の「メニューを表示」（AXShowMenu）はクリックではないので、`menu` から出す
        button.menu = menu
        attachedButton = button
    }

    private static func findStatusBarButton() -> NSStatusBarButton? {
        // `NSStatusBarWindow` は非公開の型なので、型ではなく中身のビューで見分ける
        NSApp.windows.lazy.compactMap { $0.contentView.flatMap(findStatusBarButton(in:)) }.first
    }

    private static func findStatusBarButton(in view: NSView) -> NSStatusBarButton? {
        if let button = view as? NSStatusBarButton { return button }
        return view.subviews.lazy.compactMap(findStatusBarButton(in:)).first
    }

    private func item(_ title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    @objc private func rightClicked(_ recognizer: NSClickGestureRecognizer) {
        guard recognizer.state == .ended, let button = recognizer.view else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func showAbout() {
        // `LSUIElement` のアプリは前面に出さないと、パネルがほかのアプリの後ろに開く
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func showSettings() {
        openSettings?()
    }

    @objc private func openReleases() {
        guard let url = Self.releasesURL else { return }
        openURL(url)
    }
}
