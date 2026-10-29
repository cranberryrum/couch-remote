import CoreGraphics
import Foundation

/// Every feel-related knob in one place. Tweak these while testing on the phone.
enum Tuning {
    // MARK: Pointer

    /// Base multiplier from finger points to Mac points at slow speed.
    static let pointerSensitivity: CGFloat = 1.8
    /// Extra gain per point/second of finger speed:
    /// gain = min(maxPointerGain, sensitivity * (1 + acceleration * speed)).
    static let pointerAcceleration: CGFloat = 0.0012
    static let maxPointerGain: CGFloat = 7

    // MARK: Scroll

    /// Finger points to scroll pixels.
    static let scrollGain: CGFloat = 1.6
    /// Exponential velocity decay per second after lift-off (higher = shorter glide).
    static let momentumDecay: CGFloat = 3.2
    /// Minimum release speed (pt/s) that starts momentum.
    static let momentumStartSpeed: CGFloat = 200
    /// Momentum ends when speed falls below this (pt/s).
    static let momentumStopSpeed: CGFloat = 25

    // MARK: Taps

    /// A touch that strays further than this is a drag, not a tap; the cursor also
    /// ignores motion inside this radius so a tap can't nudge it.
    static let tapSlop: CGFloat = 6
    static let tapMaxDuration: TimeInterval = 0.25
    static let doubleTapInterval: TimeInterval = 0.30
}
