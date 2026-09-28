import Observation
import ServiceManagement

@MainActor
@Observable
public final class LoginItem {
    public private(set) var isEnabled: Bool
    public private(set) var error: String?

    public init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    public func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
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
}
