import CoreGraphics
import Foundation

/// Every feel- and timing-related knob in one place. Tweak these while testing on the phone.
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

    // MARK: Pinch (zoom)

    /// Change in the distance between two fingers (points) per zoom step (one ⌘= or ⌘-).
    static let pinchStepDistance: CGFloat = 36
    /// Two fingers count as a pinch (not a scroll) when their spread changes by more than this
    /// multiple of how far their midpoint travels. Raise it if scrolls are misread as pinches.
    static let pinchBias: CGFloat = 1.6

    // MARK: Hold-to-repeat buttons (seek, volume, brightness, zoom)

    /// Hold this long before a pressed button starts repeating.
    static let repeatDelay: Duration = .milliseconds(350)
    static let repeatInterval: Duration = .milliseconds(90)

    // MARK: Taps and drag

    /// A touch that strays further than this is a drag, not a tap; the cursor also
    /// ignores motion inside this radius so a tap can't nudge it.
    static let tapSlop: CGFloat = 6
    static let tapMaxDuration: TimeInterval = 0.25
    /// Max gap between taps for a double-click, and for tap-then-hold-and-move to become a drag.
    static let doubleTapInterval: TimeInterval = 0.30

    // MARK: Connection

    /// After an unexpected drop (or returning to the foreground), keep retrying the same Mac this long.
    static let reconnectWindow: TimeInterval = 15
    /// After pairing, how long to wait for the new Mac to show up in Bonjour before giving up.
    static let pairConnectWindow: TimeInterval = 20
    /// A single connection attempt (TLS + hello/welcome) that takes longer than this is abandoned.
    static let connectAttemptTimeout: TimeInterval = 8

    // MARK: Screen

    /// Without a touch for this long, the phone is allowed to auto-lock again.
    static let idleLockDelay: TimeInterval = 5 * 60

    // MARK: Sleep timer

    static let sleepTimerMinutes = [15, 30, 45, 60, 90]
}
