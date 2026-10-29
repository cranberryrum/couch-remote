import IOKit.pwr_mgt

/// Holds a "prevent display sleep" power assertion while a phone is connected.
final class KeepAwake {
    // IOKit's kIOPMAssertPreventUserIdleDisplaySleep is a mutable global in Swift
    // (not usable under strict concurrency); this is its literal value.
    private static let assertionType = "PreventUserIdleDisplaySleep" as CFString

    private var assertionID = IOPMAssertionID(0)
    private var isHeld = false

    func acquire(reason: String) {
        guard !isHeld else { return }
        let result = IOPMAssertionCreateWithName(
            Self.assertionType,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )
        isHeld = result == kIOReturnSuccess
    }

    func release() {
        guard isHeld else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = IOPMAssertionID(0)
        isHeld = false
    }
}
