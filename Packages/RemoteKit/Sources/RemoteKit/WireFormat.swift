import Foundation

/// Payload layout: `[tag: u8][fields…]`, integers big-endian, floats as IEEE-754 bit patterns,
/// UUIDs as 16 raw bytes.
///
///     hello      0x00  u8 version, uuid deviceID, uuid pairingID, 32-byte proof, utf8 name (rest)
///     move       0x01  f32 dx, f32 dy
///     button     0x02  u8 button, u8 state
///     click      0x03  u8 button, u8 count
///     scroll     0x04  f32 dx, f32 dy, u8 phase
///     media      0x05  u8 key
///     key        0x06  u8 key, [u8 modifiers]   (modifiers optional: stage-1 payloads still decode)
///     ping       0x07  u64 timestamp
///     pong       0x08  u64 timestamp
///     welcome    0x09  u8 version, uuid macID, utf8 name (rest)
///     macStatus  0x0A  u8 count, count × (u8 key, u8 length, value)   unknown keys are skipped
///                        key 1: u32 sleep-timer seconds remaining
///     text       0x0B  utf8 (rest)
///     sleepTimer 0x0C  u16 minutes (0 = cancel)
///     disconnect 0x0D  u8 reason
///
/// `hello` and `welcome` start with the protocol version so a mismatch can be reported
/// even when the rest of the layout has changed.
public enum WireError: Error, Equatable, Sendable {
    case frameTooLarge(Int)
    case emptyFrame
    case unknownTag(UInt8)
    case truncated
    case invalidValue
    case trailingBytes
}

private enum Tag: UInt8 {
    case hello = 0x00
    case move = 0x01
    case button = 0x02
    case click = 0x03
    case scroll = 0x04
    case media = 0x05
    case key = 0x06
    case ping = 0x07
    case pong = 0x08
    case welcome = 0x09
    case macStatus = 0x0A
    case text = 0x0B
    case sleepTimer = 0x0C
    case disconnect = 0x0D
}

private enum StatusKey: UInt8 {
    case sleepTimerRemaining = 1
}

extension Message {
    public static let proofLength = 32

    /// The payload only (no length prefix). Use `Frame.encode` for the wire form.
    public func encoded() -> [UInt8] {
        var w = Writer()
        switch self {
        case .hello(let version, let deviceID, let pairingID, let name, let proof):
            w.u8(Tag.hello.rawValue)
            w.u8(version)
            w.append(deviceID.wireBytes)
            w.append(pairingID.wireBytes)
            w.append(proof.count == Message.proofLength ? proof : [UInt8](repeating: 0, count: Message.proofLength))
            w.append(Array(Message.truncated(name, maxBytes: Message.maxNameLength * 4).utf8))
        case .welcome(let version, let macID, let name):
            w.u8(Tag.welcome.rawValue)
            w.u8(version)
            w.append(macID.wireBytes)
            w.append(Array(Message.truncated(name, maxBytes: Message.maxNameLength * 4).utf8))
        case .move(let dx, let dy):
            w.u8(Tag.move.rawValue)
            w.f32(dx)
            w.f32(dy)
        case .button(let button, let state):
            w.u8(Tag.button.rawValue)
            w.u8(button.rawValue)
            w.u8(state.rawValue)
        case .click(let button, let count):
            w.u8(Tag.click.rawValue)
            w.u8(button.rawValue)
            w.u8(count)
        case .scroll(let dx, let dy, let phase):
            w.u8(Tag.scroll.rawValue)
            w.f32(dx)
            w.f32(dy)
            w.u8(phase.rawValue)
        case .media(let key):
            w.u8(Tag.media.rawValue)
            w.u8(key.rawValue)
        case .key(let key, let modifiers):
            w.u8(Tag.key.rawValue)
            w.u8(key.rawValue)
            w.u8(modifiers.rawValue)
        case .text(let text):
            w.u8(Tag.text.rawValue)
            w.append(Array(Message.truncated(text, maxBytes: Message.maxTextBytes).utf8))
        case .sleepTimer(let minutes):
            w.u8(Tag.sleepTimer.rawValue)
            w.u16(minutes)
        case .macStatus(let status):
            w.u8(Tag.macStatus.rawValue)
            var entries = Writer()
            var count: UInt8 = 0
            if let remaining = status.sleepTimerRemaining {
                entries.u8(StatusKey.sleepTimerRemaining.rawValue)
                entries.u8(4)
                entries.u32(UInt32(clamping: max(0, remaining)))
                count += 1
            }
            w.u8(count)
            w.append(entries.bytes)
        case .disconnect(let reason):
            w.u8(Tag.disconnect.rawValue)
            w.u8(reason.rawValue)
        case .ping(let timestamp):
            w.u8(Tag.ping.rawValue)
            w.u64(timestamp)
        case .pong(let timestamp):
            w.u8(Tag.pong.rawValue)
            w.u64(timestamp)
        }
        return w.bytes
    }

    public init(payload: [UInt8]) throws(WireError) {
        var r = Reader(payload)
        let rawTag = try r.u8()
        guard let tag = Tag(rawValue: rawTag) else { throw .unknownTag(rawTag) }
        switch tag {
        case .hello:
            let version = try r.u8()
            if version != Message.protocolVersion {
                // Layout may differ: report the version and ignore the rest.
                _ = r.rest()
                self = .hello(protocolVersion: version, deviceID: .zero, pairingID: .zero, name: "", proof: [])
            } else {
                let deviceID = try r.uuid()
                let pairingID = try r.uuid()
                let proof = try r.bytes(Message.proofLength)
                let name = String(decoding: r.rest(), as: UTF8.self)
                self = .hello(protocolVersion: version, deviceID: deviceID, pairingID: pairingID, name: name, proof: proof)
            }
        case .welcome:
            let version = try r.u8()
            if version != Message.protocolVersion {
                _ = r.rest()
                self = .welcome(protocolVersion: version, macID: .zero, name: "")
            } else {
                let macID = try r.uuid()
                self = .welcome(protocolVersion: version, macID: macID, name: String(decoding: r.rest(), as: UTF8.self))
            }
        case .move:
            self = try .move(dx: r.f32(), dy: r.f32())
        case .button:
            self = try .button(r.value(MouseButton.self), r.value(ButtonState.self))
        case .click:
            self = try .click(r.value(MouseButton.self), count: r.u8())
        case .scroll:
            self = try .scroll(dx: r.f32(), dy: r.f32(), phase: r.value(ScrollPhase.self))
        case .media:
            self = try .media(r.value(MediaKey.self))
        case .key:
            let key = try r.value(KeyCode.self)
            var modifiers: KeyModifiers = []
            if !r.isAtEnd { modifiers = KeyModifiers(rawValue: try r.u8()) }
            self = .key(key, modifiers: modifiers)
        case .text:
            self = .text(String(decoding: r.rest(), as: UTF8.self))
        case .sleepTimer:
            self = try .sleepTimer(minutes: r.u16())
        case .macStatus:
            var status = MacStatus()
            let count = try r.u8()
            for _ in 0..<count {
                let key = try r.u8()
                let length = Int(try r.u8())
                let value = try r.bytes(length)
                switch StatusKey(rawValue: key) {
                case .sleepTimerRemaining:
                    guard length == 4 else { throw .invalidValue }
                    status.sleepTimerRemaining = Int(value.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
                case nil:
                    break // a newer Mac may send fields we don't know yet
                }
            }
            self = .macStatus(status)
        case .disconnect:
            self = try .disconnect(r.value(DisconnectReason.self))
        case .ping:
            self = try .ping(timestamp: r.u64())
        case .pong:
            self = try .pong(timestamp: r.u64())
        }
        guard r.isAtEnd else { throw .trailingBytes }
    }
}

extension UUID {
    static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    var wireBytes: [UInt8] { withUnsafeBytes(of: uuid) { Array($0) } }

    init(wireBytes bytes: [UInt8]) {
        var raw: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        withUnsafeMutableBytes(of: &raw) { $0.copyBytes(from: bytes.prefix(16)) }
        self.init(uuid: raw)
    }
}

private struct Writer {
    var bytes: [UInt8] = []

    mutating func u8(_ v: UInt8) { bytes.append(v) }

    mutating func append(_ v: [UInt8]) { bytes.append(contentsOf: v) }

    mutating func u16(_ v: UInt16) {
        bytes.append(UInt8(truncatingIfNeeded: v >> 8))
        bytes.append(UInt8(truncatingIfNeeded: v))
    }

    mutating func u32(_ v: UInt32) {
        for shift in stride(from: 24, through: 0, by: -8) {
            bytes.append(UInt8(truncatingIfNeeded: v >> UInt32(shift)))
        }
    }

    mutating func u64(_ v: UInt64) {
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8(truncatingIfNeeded: v >> UInt64(shift)))
        }
    }

    mutating func f32(_ v: Float) { u32(v.bitPattern) }
}

private struct Reader {
    private let bytes: [UInt8]
    private var index = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var isAtEnd: Bool { index == bytes.count }

    mutating func u8() throws(WireError) -> UInt8 {
        guard index < bytes.count else { throw .truncated }
        defer { index += 1 }
        return bytes[index]
    }

    mutating func u16() throws(WireError) -> UInt16 {
        let high = UInt16(try u8())
        let low = UInt16(try u8())
        return (high << 8) | low
    }

    mutating func u32() throws(WireError) -> UInt32 {
        var v: UInt32 = 0
        for _ in 0..<4 { v = (v << 8) | UInt32(try u8()) }
        return v
    }

    mutating func u64() throws(WireError) -> UInt64 {
        var v: UInt64 = 0
        for _ in 0..<8 { v = (v << 8) | UInt64(try u8()) }
        return v
    }

    mutating func f32() throws(WireError) -> Float { Float(bitPattern: try u32()) }

    mutating func bytes(_ count: Int) throws(WireError) -> [UInt8] {
        guard bytes.count - index >= count else { throw .truncated }
        defer { index += count }
        return Array(bytes[index..<(index + count)])
    }

    mutating func uuid() throws(WireError) -> UUID {
        UUID(wireBytes: try bytes(16))
    }

    mutating func value<E: RawRepresentable>(_: E.Type) throws(WireError) -> E where E.RawValue == UInt8 {
        guard let v = E(rawValue: try u8()) else { throw .invalidValue }
        return v
    }

    mutating func rest() -> [UInt8] {
        defer { index = bytes.count }
        return Array(bytes[index...])
    }
}
