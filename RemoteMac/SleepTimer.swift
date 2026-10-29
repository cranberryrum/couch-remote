import Foundation
import IOKit
import IOKit.pwr_mgt
import Observation

/// The sleep timer lives on the Mac so it keeps running if the phone locks or disconnects.
@Observable
final class SleepTimer {
    private(set) var endDate: Date?

    func start(minutes: Int) {
        endDate = Date().addingTimeInterval(TimeInterval(max(1, minutes)) * 60)
    }

    func cancel() {
        endDate = nil
    }

    /// Whole seconds left (rounded up), or nil when no timer is running.
    func remainingSeconds(now: Date = Date()) -> Int? {
        guard let endDate else { return nil }
        return max(0, Int(endDate.timeIntervalSince(now).rounded(.up)))
    }

    /// True exactly once when the timer runs out, clearing it.
    func consumeIfExpired(now: Date = Date()) -> Bool {
        guard let endDate, endDate <= now else { return false }
        self.endDate = nil
        return true
    }
}

/// Puts the whole system to sleep without needing root.
enum SystemSleep {
    static func now() {
        // IOPMSleepSystem is callable by a normal user process.
        let port = IOPMFindPowerManagement(mach_port_t(MACH_PORT_NULL))
        if port != 0 {
            let result = IOPMSleepSystem(port)
            IOServiceClose(port)
            if result == kIOReturnSuccess { return }
        }
        // Fallback: `pmset sleepnow` also needs no privileges.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["sleepnow"]
        try? process.run()
    }
}
