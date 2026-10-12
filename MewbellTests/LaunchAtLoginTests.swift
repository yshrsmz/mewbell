import Testing

@testable import Mewbell

/// 呼び出しを記録し、用意した状態を返す `LoginItemService`。
@MainActor
final class FakeLoginItemService: LoginItemService {
    struct Failure: Error {}

    var status: LoginItemStatus = .notRegistered
    /// `register` の後の状態
    var statusAfterRegister: LoginItemStatus = .enabled
    var fails = false
    var calls: [String] = []

    func register() throws {
        calls.append("register")
        if fails { throw Failure() }
        status = statusAfterRegister
    }

    func unregister() throws {
        calls.append("unregister")
        if fails { throw Failure() }
        status = .notRegistered
    }

    func openSystemSettings() {
        calls.append("openSystemSettings")
    }
}

@MainActor
struct LaunchAtLoginTests {
    @Test func registersAndReadsTheStatusBack() {
        let service = FakeLoginItemService()
        let launch = LaunchAtLogin(service: service)
        #expect(!launch.isOn)
        launch.set(true)
        #expect(service.calls == ["register"])
        #expect(launch.status == .enabled)
        #expect(launch.isOn)
        launch.set(false)
        #expect(launch.status == .notRegistered)
    }

    @Test func goesBackToTheSystemStatusWhenRegisteringFails() {
        let service = FakeLoginItemService()
        service.fails = true
        let launch = LaunchAtLogin(service: service)
        launch.set(true)
        #expect(launch.status == .notRegistered)
        #expect(!launch.isOn)
        #expect(launch.failed)
        service.fails = false
        launch.set(true)
        #expect(!launch.failed)
    }

    @Test func reportsThatApprovalIsNeeded() {
        let service = FakeLoginItemService()
        service.statusAfterRegister = .requiresApproval
        let launch = LaunchAtLogin(service: service)
        launch.set(true)
        #expect(launch.status == .requiresApproval)
        // 承認待ちでも登録はしているので、スイッチは ON のまま
        #expect(launch.isOn)
        #expect(!launch.failed)
        launch.openSystemSettings()
        #expect(service.calls == ["register", "openSystemSettings"])
    }

    @Test func picksUpARemovalFromSystemSettings() {
        let service = FakeLoginItemService()
        service.status = .enabled
        let launch = LaunchAtLogin(service: service)
        #expect(launch.isOn)
        service.status = .notRegistered
        launch.refresh()
        #expect(!launch.isOn)
    }
}
