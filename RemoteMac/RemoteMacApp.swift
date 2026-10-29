import AppKit
import SwiftUI

@main
struct RemoteMacApp: App {
    private let model = AppModel.shared

    init() {
        model.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            Image(systemName: model.server.isClientConnected
                ? "iphone.radiowaves.left.and.right"
                : "iphone")
        }
    }
}

private struct MenuView: View {
    let model: AppModel

    var body: some View {
        Text("CouchRemote")

        Divider()

        Label(
            model.accessibilityGranted ? "Accessibility granted" : "Accessibility NOT granted",
            systemImage: model.accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        )
        Label(
            model.server.isListening ? "Listening" : "Not listening",
            systemImage: model.server.isListening ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash"
        )
        Label(connectionText, systemImage: model.server.isClientConnected ? "iphone.gen3" : "iphone.slash")

        Divider()

        Button("Open Accessibility Settings") { AccessibilityPermission.openSettings() }

        Divider()

        Button("Quit") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var connectionText: String {
        guard model.server.isClientConnected else { return "No device connected" }
        return "Connected: \(model.server.deviceName ?? "device")"
    }
}
