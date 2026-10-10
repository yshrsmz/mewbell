import Foundation
import Observation
import ServiceManagement
import os

/// ログイン項目の登録の状態。
enum LoginItemStatus: Sendable, Equatable {
    case enabled
    /// 登録したが、ユーザーの承認を待っている
    case requiresApproval
    case notRegistered
    /// アプリを見つけられない（登録できない）
    case notFound
}

/// ログイン項目（メインアプリ）の登録。テストで差し替えられるようにプロトコルにする。
@MainActor
protocol LoginItemService {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

/// `SMAppService.mainApp` を使う。
struct MainAppLoginItem: LoginItemService {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered: .notRegistered
        case .notFound: .notFound
        @unknown default: .notFound
        }
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// 何も登録しない（テストのホストや SwiftUI プレビュー用）。
struct InertLoginItem: LoginItemService {
    var status: LoginItemStatus = .notRegistered
    func register() throws {}
    func unregister() throws {}
    func openSystemSettings() {}
}

/// 「ログイン時に起動する」の表示の状態。登録の状態は保存せず、いつも macOS から読む。
@MainActor
@Observable
final class LaunchAtLogin {
    private(set) var status: LoginItemStatus
    /// 直前の登録・解除に失敗した
    private(set) var failed = false

    @ObservationIgnored private static let logger = Logger(category: "Settings")
    @ObservationIgnored private let service: any LoginItemService

    init(service: any LoginItemService) {
        self.service = service
        status = service.status
    }

    /// 登録されている（承認待ちを含む）。切り替えの表示に使う
    var isOn: Bool { status == .enabled || status == .requiresApproval }

    /// macOS の登録の状態を読み直す（設定ウィンドウを開いたとき。システム設定で外されたときにずれないように）。
    func refresh() {
        status = service.status
    }

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            failed = false
        } catch {
            // システムのエラーの文は画面に出さず、ログに残すだけにする
            Self.logger.error("Could not change the login item: \(String(describing: error))")
            failed = true
        }
        refresh()
    }

    func openSystemSettings() {
        service.openSystemSettings()
    }
}
