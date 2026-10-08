import Foundation

enum LaunchContext {
    /// テストのホストや SwiftUI プレビューとして起動されたかどうか。
    /// このときは二重起動の判定や gh の実行を行わない（開発者の環境に左右されずにテストやプレビューを動かすため）。
    static var isTestHostOrPreview: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil || environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}
