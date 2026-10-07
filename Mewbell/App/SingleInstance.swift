import AppKit

/// 同じ Bundle ID のアプリが複数起動したとき、後から起動した方を終了させるための判定。
enum SingleInstance {
    struct Instance: Equatable {
        let processIdentifier: pid_t
        let launchDate: Date?
    }

    /// `current` より先に起動した同じアプリが `others` にあれば `true` を返す。
    /// 起動時刻が同じか不明なときは PID の小さい方を先とみなし、同時に起動しても片方だけが残るようにする。
    static func shouldTerminate(current: Instance, others: [Instance]) -> Bool {
        others.contains { other in
            guard other.processIdentifier != current.processIdentifier else { return false }
            switch (other.launchDate, current.launchDate) {
            case (let otherDate?, let currentDate?) where otherDate != currentDate:
                return otherDate < currentDate
            default:
                return other.processIdentifier < current.processIdentifier
            }
        }
    }

    /// 先に起動した Mewbell があれば、それを前面に出してこのプロセスを終了する。
    /// テストのホストとして起動されたときは判定しない（起動中の Mewbell があってもテストを走らせられるように）。
    @MainActor
    static func terminateIfAnotherInstanceIsRunning() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
            let bundleIdentifier = Bundle.main.bundleIdentifier
        else { return }

        let currentApp = NSRunningApplication.current
        let otherApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != currentApp.processIdentifier && !$0.isTerminated }
        let current = Instance(processIdentifier: currentApp.processIdentifier, launchDate: currentApp.launchDate)
        let others = otherApps.map { Instance(processIdentifier: $0.processIdentifier, launchDate: $0.launchDate) }

        guard shouldTerminate(current: current, others: others) else { return }
        otherApps.first?.activate()
        exit(EXIT_SUCCESS)
    }
}
