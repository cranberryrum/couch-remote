import Observation

@Observable
final class AppModel {
    static let shared = AppModel()

    let server = RemoteServer()
    private(set) var accessibilityGranted = AccessibilityPermission.isTrusted

    @ObservationIgnored private var started = false

    func start() {
        guard !started else { return }
        started = true
        if !AccessibilityPermission.isTrusted { AccessibilityPermission.requestPrompt() }
        server.start()
        // Trust can be granted while we run; keep the menu honest.
        Task {
            while !Task.isCancelled {
                accessibilityGranted = AccessibilityPermission.isTrusted
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }
}
