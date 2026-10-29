import AppKit
import SwiftUI

/// An AppKit-owned window: SwiftUI `Window` scenes auto-open at launch, which a
/// menu-bar-only app must not do.
@MainActor
final class PairingWindowController {
    static let shared = PairingWindowController()

    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let hosting = NSHostingController(rootView: PairingView(model: model, close: { [weak self] in self?.close() }))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Pair New iPhone"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            self.window = window
        }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
    }
}

struct PairingView: View {
    let model: AppModel
    let close: () -> Void

    var body: some View {
        let pairing = model.pairing
        VStack(spacing: 16) {
            if let pending = pairing.pending {
                Text("Pair a new iPhone")
                    .font(.title2.bold())
                Text("In CouchRemote on your iPhone, tap “Pair another Mac” and scan this code, or scan it with the Camera app.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let image = QRCode.image(for: pending.invite.url.absoluteString) {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 240, height: 240)
                        .padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                }

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = max(0, Int(pending.expiresAt.timeIntervalSince(context.date)))
                    Text("Code expires in \(left / 60):\(String(format: "%02d", left % 60))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Button("Cancel") {
                    model.cancelPairing()
                    close()
                }
            } else if let name = pairing.lastPairedPhoneName {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("Paired with \(name)")
                    .font(.title2.bold())
                    .task {
                        try? await Task.sleep(for: .seconds(1.5))
                        close()
                    }
            } else {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("This code expired")
                    .font(.title2.bold())
                HStack {
                    Button("New Code") { model.beginPairing() }
                        .keyboardShortcut(.defaultAction)
                    Button("Close", action: close)
                }
            }
        }
        .padding(28)
        .frame(width: 380)
    }
}
