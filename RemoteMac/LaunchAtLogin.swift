import Observation
import OSLog
import ServiceManagement

@Observable
final class LaunchAtLogin {
    private(set) var isEnabled = SMAppService.mainApp.status == .enabled

    @ObservationIgnored private let log = Logger(subsystem: "com.adityakolte.couchremote.mac", category: "login-item")

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("Launch at login change failed: \(error.localizedDescription)")
        }
        refresh()
    }
}
