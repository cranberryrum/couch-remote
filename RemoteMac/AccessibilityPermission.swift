import AppKit
import ApplicationServices

/// Posting synthetic input requires the Accessibility permission, which macOS ties
/// to the app's code signature (so keep signing consistent between rebuilds).
enum AccessibilityPermission {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Checks trust and, if missing, shows the system prompt.
    @discardableResult
    static func requestPrompt() -> Bool {
        // Literal value of kAXTrustedCheckOptionPrompt (a mutable global in Swift).
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
