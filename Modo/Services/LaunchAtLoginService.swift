import Foundation
import ServiceManagement

/// Wraps SMAppService.mainApp so the user can toggle "Open at Login" from
/// Preferences. Available on macOS 13+; on older systems the toggle is hidden.
enum LaunchAtLoginService {

    static var isAvailable: Bool {
        if #available(macOS 13.0, *) { return true }
        return false
    }

    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    /// Returns true on success. Failures are surfaced to the caller so the UI
    /// can keep the toggle in sync if registration was denied.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }
}
