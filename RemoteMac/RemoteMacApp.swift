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

    private var server: RemoteServer { model.server }

    var body: some View {
        Text("CouchRemote")

        Divider()

        Label(
            model.accessibilityGranted ? "Accessibility granted" : "Accessibility NOT granted",
            systemImage: model.accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        )
        Label(
            listeningText,
            systemImage: server.isListening ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash"
        )
        Label(connectionText, systemImage: server.isClientConnected ? "iphone.gen3" : "iphone.slash")
        if let notice = server.notice {
            Label(notice, systemImage: "exclamationmark.triangle")
        }
        if let phone = server.connectedPhone {
            Button("Disconnect \(phone.name)") { server.disconnectActive(reason: .userRequested) }
        }

        Divider()

        Toggle("Accept connections", isOn: Binding(
            get: { server.isAccepting },
            set: { server.setAccepting($0) }
        ))
        Button("Pair New iPhone…") { model.beginPairing() }
        Menu("Paired iPhones (\(model.pairing.phones.count))") {
            if model.pairing.phones.isEmpty {
                Text("None yet")
            } else {
                ForEach(model.pairing.phones) { phone in
                    Button("Forget “\(phone.name)”") { server.forgetPhone(phone.pairingID) }
                }
            }
        }

        if let remaining = model.sleepTimer.remainingSeconds() {
            Divider()
            Label("Sleeping in \(clock(remaining))", systemImage: "moon.zzz.fill")
            Button("Cancel sleep timer") {
                model.sleepTimer.cancel()
                server.pushStatus()
            }
        }

        Divider()

        Toggle("Launch at login", isOn: Binding(
            get: { model.launchAtLogin.isEnabled },
            set: { model.launchAtLogin.set($0) }
        ))
        Button("Open Accessibility Settings") { AccessibilityPermission.openSettings() }

        Divider()

        Button("Quit") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var listeningText: String {
        if !server.isAccepting { return "Not accepting connections" }
        return server.isListening ? "Listening" : "Starting…"
    }

    private var connectionText: String {
        guard let phone = server.connectedPhone else { return "No device connected" }
        return "Connected: \(phone.name)"
    }

    private func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
