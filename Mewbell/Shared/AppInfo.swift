import Foundation

/// 画面に出すアプリ名と、表示・送信に使うバージョン。Debug ビルドには印を付けて、Release ビルドと見分けられるようにする。
/// Info.plist の値は変えない（配布物の検査とリリースのバージョンの管理をそのままにするため）。
enum AppInfo {
    private static let shortVersion =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    #if DEBUG
        static let name = "Mewbell (dev)"
        static let version = "\(shortVersion)-dev"
    #else
        static let name = "Mewbell"
        static let version = shortVersion
    #endif
}
