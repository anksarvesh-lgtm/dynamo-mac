import Foundation
import ServiceManagement

/// Launch at login via SMAppService (public, macOS 13+). Works for ad-hoc signed apps; macOS may ask
/// the user to approve Island in System Settings › General › Login Items.
@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
