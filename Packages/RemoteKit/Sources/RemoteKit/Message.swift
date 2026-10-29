public enum MouseButton: UInt8, Sendable, CaseIterable {
    case left = 0
    case right = 1
}

public enum ButtonState: UInt8, Sendable {
    case up = 0
    case down = 1
}

/// Finger phases mirror a trackpad: the fingers drive `began…ended`, then the
/// phone synthesizes `momentum*` events after lift-off (browsers don't
/// generate their own momentum, they rely on the OS-supplied phases).
public enum ScrollPhase: UInt8, Sendable {
    case began = 0
    case changed = 1
    case ended = 2
    case momentumBegan = 3
    case momentumChanged = 4
    case momentumEnded = 5
}

public enum MediaKey: UInt8, Sendable, CaseIterable {
    case playPause = 0
    case next = 1
    case previous = 2
    case volumeUp = 3
    case volumeDown = 4
}

public enum KeyCode: UInt8, Sendable, CaseIterable {
    case arrowLeft = 0
    case arrowRight = 1
    case space = 2
}

public enum Message: Sendable, Equatable {
    /// Sent once by the phone right after connecting so the Mac can show who is connected.
    case hello(name: String)
    /// Relative cursor motion in Mac points. Already acceleration-scaled by the phone.
    case move(dx: Float, dy: Float)
    /// Raw button press/release; while held, `move` becomes a drag.
    case button(MouseButton, ButtonState)
    /// One complete down/up pair. `count` is the click-state of *this* click
    /// (1 = single, 2 = the second click of a double-click, 3 = triple).
    case click(MouseButton, count: UInt8)
    /// Pixel deltas, content-follows-finger ("natural") sign convention.
    case scroll(dx: Float, dy: Float, phase: ScrollPhase)
    case media(MediaKey)
    case key(KeyCode)
    /// `timestamp` is opaque to the Mac; it is echoed back unchanged in `pong`.
    case ping(timestamp: UInt64)
    case pong(timestamp: UInt64)
}
