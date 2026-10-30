import Foundation
import Observation

@Observable
final class AppModel {
    static let shared = AppModel()

    let pairing: PairingStore
    let sleepTimer: SleepTimer
    let server: RemoteServer
    let launchAtLogin = LaunchAtLogin()
    private(set) var accessibilityGranted = AccessibilityPermission.isTrusted

    @ObservationIgnored private var started = false

    init() {
        let pairing = PairingStore()
        let sleepTimer = SleepTimer()
        self.pairing = pairing
        self.sleepTimer = sleepTimer
        server = RemoteServer(pairing: pairing, sleepTimer: sleepTimer)
    }

    func start() {
        guard !started else { return }
        started = true
        server.start()

        // First run: a welcome window, not a system dialog thrown at the user the moment the app opens.
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            OnboardingWindowController.shared.showIfNeeded(model: self)
        }

        #if DEBUG
        // Test hook: with COUCHREMOTE_DEBUG_PAIRING_URL_FILE set, open a pairing invite at
        // launch and write its URL to that file (lets the simulator pair without a camera).
        if let path = ProcessInfo.processInfo.environment["COUCHREMOTE_DEBUG_PAIRING_URL_FILE"] {
            let invite = server.beginPairing()
            try? invite.url.absoluteString.write(toFile: path, atomically: true, encoding: .utf8)
        }
        #endif

        Task {
            while !Task.isCancelled {
                accessibilityGranted = AccessibilityPermission.isTrusted
                server.tick()
                if sleepTimer.consumeIfExpired() { server.sleepSystemNow() }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func beginPairing() {
        server.beginPairing()
        PairingWindowController.shared.show(model: self)
    }

    func cancelPairing() {
        server.cancelPairing()
    }
}
