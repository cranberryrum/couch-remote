import AppKit
import SwiftUI

/// First-run setup, in a window the user can read, instead of a system dialog at launch.
/// AppKit-owned for the same reason as the pairing window: a menu-bar app must not auto-open scenes.
@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()

    private static let seenKey = "onboardingSeen"
    private var window: NSWindow?

    /// At launch: only on the first run, and only while the Mac still needs setting up.
    func showIfNeeded(model: AppModel) {
        #if DEBUG
        // Test hook: COUCHREMOTE_DEBUG_ONBOARDING=1 always opens the window at launch.
        if ProcessInfo.processInfo.environment["COUCHREMOTE_DEBUG_ONBOARDING"] != nil { return show(model: model) }
        #endif
        guard !UserDefaults.standard.bool(forKey: Self.seenKey) else { return }
        guard !AccessibilityPermission.isTrusted || model.pairing.phones.isEmpty else { return }
        show(model: model)
    }

    func show(model: AppModel) {
        UserDefaults.standard.set(true, forKey: Self.seenKey)
        if window == nil {
            let hosting = NSHostingController(rootView: OnboardingView(model: model, close: { [weak self] in self?.close() }))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Welcome to CouchRemote"
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

/// Two steps, picked by what's actually true: Accessibility first, then pairing.
/// It updates by itself when the permission is granted in System Settings.
struct OnboardingView: View {
    let model: AppModel
    let close: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .padding(.top, 4)

            Group {
                if model.accessibilityGranted {
                    pairStep
                } else {
                    accessibilityStep
                }
            }
            .transition(.opacity)
        }
        .padding(28)
        .frame(width: 420, height: 400)
        .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.25), value: model.accessibilityGranted)
        .onChange(of: model.accessibilityGranted) { _, granted in
            // The user is in System Settings when this flips: bring the next step to them.
            if granted { NSApp.activate(ignoringOtherApps: true) }
        }
    }

    private var accessibilityStep: some View {
        VStack(spacing: 12) {
            Text("Let CouchRemote control this Mac")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("macOS asks for your OK before an app can move the pointer or press keys. CouchRemote only does this for commands from an iPhone you've paired.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            Button {
                AccessibilityPermission.requestPrompt()   // also lists the app in System Settings
                AccessibilityPermission.openSettings()
            } label: {
                Text("Open Accessibility Settings")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Switch on CouchRemote there. This window updates by itself.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button("Not now", action: close)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.callout)
                .padding(.top, 2)
        }
    }

    private var pairStep: some View {
        VStack(spacing: 12) {
            Label("Accessibility is on", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout.weight(.medium))
            Text("Now pair your iPhone")
                .font(.title2.bold())
            Text("Open CouchRemote on your iPhone and tap “Pair another Mac”, then scan the code that appears here.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            Button {
                model.beginPairing()
                close()
            } label: {
                Text("Show pairing code")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            Button("Later", action: close)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.callout)
                .padding(.top, 2)
        }
    }
}
