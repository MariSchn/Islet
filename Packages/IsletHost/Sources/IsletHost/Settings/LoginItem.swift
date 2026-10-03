import Observation
import ServiceManagement

@MainActor
@Observable
public final class LoginItem {
    public private(set) var isEnabled = false
    public private(set) var requiresApproval = false
    public private(set) var error: String?

    public init() {
        refresh()
    }

    public func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        requiresApproval = status == .requiresApproval
        if requiresApproval {
            error = nil
        }
    }

    public func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        refresh()
    }

    public func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
