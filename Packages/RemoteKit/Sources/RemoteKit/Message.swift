import Foundation

// Raw values of every enum below are part of the wire format: only ever append.

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
    case brightnessUp = 5
    case brightnessDown = 6
}

public enum KeyCode: UInt8, Sendable, CaseIterable {
    case arrowLeft = 0
    case arrowRight = 1
    case space = 2
    case `return` = 3
    case backspace = 4
    case escape = 5
    case tab = 6
    case arrowUp = 7
    case arrowDown = 8
    // Letters, only the ones video-player / browser shortcuts need.
    case f = 9
    case m = 10
    case c = 11
    case k = 12
    case j = 13
    case l = 14
    case t = 15
    case w = 16
    // Browser zoom (⌘= / ⌘- / ⌘0).
    case equal = 17
    case minus = 18
    case zero = 19
}

public struct KeyModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let shift = KeyModifiers(rawValue: 1 << 1)
    public static let control = KeyModifiers(rawValue: 1 << 2)
    public static let option = KeyModifiers(rawValue: 1 << 3)
}

/// Why the Mac closed the link. The phone must not auto-retry after any of these.
public enum DisconnectReason: UInt8, Sendable, CaseIterable {
    case userRequested = 0
    case replaced = 1
    case forgotten = 2
    case serverStopped = 3
    case macSleeping = 4
    case versionMismatch = 5
    case unauthorized = 6
}

/// Mac → phone state. Encoded as tag/length/value entries so stage 3 can add
/// now-playing, volume and output device without breaking older readers
/// (unknown entries are skipped).
public struct MacStatus: Sendable, Equatable {
    /// Seconds until the Mac sleeps, or nil when no sleep timer is running.
    public var sleepTimerRemaining: Int?

    public init(sleepTimerRemaining: Int? = nil) {
        self.sleepTimerRemaining = sleepTimerRemaining
    }
}

public enum Message: Sendable, Equatable {
    /// Phone → Mac, first message on every connection. `proof` binds the claimed
    /// `pairingID` to the key actually used for the TLS-PSK handshake.
    case hello(protocolVersion: UInt8, deviceID: UUID, pairingID: UUID, name: String, proof: [UInt8])
    /// Mac → phone reply to an accepted `hello`.
    case welcome(protocolVersion: UInt8, macID: UUID, name: String)
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
    case key(KeyCode, modifiers: KeyModifiers = [])
    /// Unicode text to type. Keep each message ≤ `maxTextBytes` (see `textMessages(for:)`).
    case text(String)
    /// Phone → Mac: start a sleep timer; `0` cancels it.
    case sleepTimer(minutes: UInt16)
    case macStatus(MacStatus)
    case disconnect(DisconnectReason)
    /// `timestamp` is opaque to the Mac; it is echoed back unchanged in `pong`.
    case ping(timestamp: UInt64)
    case pong(timestamp: UInt64)
}

extension Message {
    /// Bumped whenever the wire format changes in a way an older peer can't handle. v3 appended
    /// key/media values (zoom, brightness): an older Mac would treat them as a protocol error and
    /// drop the link, so a mismatch is reported up front ("Update the other app") instead.
    public static let protocolVersion: UInt8 = 3

    public static let maxNameLength = 64
    public static let maxTextBytes = 200

    /// Splits `text` into messages that each fit `maxTextBytes`, never cutting through a
    /// character (so emoji and combining sequences survive intact).
    public static func textMessages(for text: String) -> [Message] {
        var messages: [Message] = []
        var chunk = ""
        var chunkBytes = 0
        for character in text {
            let bytes = character.utf8.count
            if chunkBytes + bytes > maxTextBytes, !chunk.isEmpty {
                messages.append(.text(chunk))
                chunk = ""
                chunkBytes = 0
            }
            chunk.append(character)
            chunkBytes += bytes
        }
        if !chunk.isEmpty { messages.append(.text(chunk)) }
        return messages
    }

    /// `text` cut at a character boundary to at most `maxBytes` UTF-8 bytes.
    static func truncated(_ text: String, maxBytes: Int) -> String {
        var result = ""
        var bytes = 0
        for character in text {
            bytes += character.utf8.count
            if bytes > maxBytes { break }
            result.append(character)
        }
        return result
    }
}
