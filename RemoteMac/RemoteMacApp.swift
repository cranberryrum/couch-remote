import AppKit
import RemoteKit
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
            Image(systemName: !model.accessibilityGranted
                ? "exclamationmark.triangle"
                : (model.server.isClientConnected ? "iphone.radiowaves.left.and.right" : "iphone"))
        }
    }
}

private struct MenuView: View {
    let model: AppModel

    private var server: RemoteServer { model.server }

    var body: some View {
        Text("CouchRemote")

        Divider()

        if !model.accessibilityGranted {
            Button {
                OnboardingWindowController.shared.show(model: model)
            } label: {
                Label("Allow Accessibility to start…", systemImage: "exclamationmark.triangle.fill")
            }
        }
        if let phone = server.connectedPhone {
            Label("Connected: \(phone.name)", systemImage: "iphone.gen3")
            Button("Disconnect") { server.disconnectActive(reason: .userRequested) }
        } else {
            Label(statusText, systemImage: server.isListening && server.isAccepting
                ? "antenna.radiowaves.left.and.right"
                : "antenna.radiowaves.left.and.right.slash")
        }
        if let notice = server.notice {
            Label(notice, systemImage: "exclamationmark.triangle")
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

        Divider()

        Menu("Made by \(Creator.name)") {
            Link(Creator.websiteLabel, destination: Creator.website)
            Link("\(Creator.twitterLabel) on X", destination: Creator.twitter)
        }

        Button("Quit") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusText: String {
        if !server.isAccepting { return "Not accepting connections" }
        return server.isListening ? "Ready: waiting for your iPhone" : "Starting…"
    }

    private func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
