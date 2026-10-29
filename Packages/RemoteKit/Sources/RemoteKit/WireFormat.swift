/// Payload layout: `[tag: u8][fields…]`, integers big-endian, floats as IEEE-754 bit patterns.
///
///     hello   0x00  utf8 name (rest of payload)
///     move    0x01  f32 dx, f32 dy
///     button  0x02  u8 button, u8 state
///     click   0x03  u8 button, u8 count
///     scroll  0x04  f32 dx, f32 dy, u8 phase
///     media   0x05  u8 key
///     key     0x06  u8 key
///     ping    0x07  u64 timestamp
///     pong    0x08  u64 timestamp
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
}

extension Message {
    public static let maxNameLength = 64

    /// The payload only (no length prefix). Use `Frame.encode` for the wire form.
    public func encoded() -> [UInt8] {
        var w = Writer()
        switch self {
        case .hello(let name):
            w.u8(Tag.hello.rawValue)
            w.append(Array(String(name.prefix(Message.maxNameLength)).utf8))
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
        case .key(let key):
            w.u8(Tag.key.rawValue)
            w.u8(key.rawValue)
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
            self = .hello(name: String(decoding: r.rest(), as: UTF8.self))
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
            self = try .key(r.value(KeyCode.self))
        case .ping:
            self = try .ping(timestamp: r.u64())
        case .pong:
            self = try .pong(timestamp: r.u64())
        }
        guard r.isAtEnd else { throw .trailingBytes }
    }
}

private struct Writer {
    var bytes: [UInt8] = []

    mutating func u8(_ v: UInt8) { bytes.append(v) }

    mutating func append(_ v: [UInt8]) { bytes.append(contentsOf: v) }

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

    mutating func value<E: RawRepresentable>(_: E.Type) throws(WireError) -> E where E.RawValue == UInt8 {
        guard let v = E(rawValue: try u8()) else { throw .invalidValue }
        return v
    }

    mutating func rest() -> [UInt8] {
        defer { index = bytes.count }
        return Array(bytes[index...])
    }
}
