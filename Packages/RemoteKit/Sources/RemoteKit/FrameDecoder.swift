/// Length-prefixed framing: `[length: u32 big-endian][payload]`.
public enum Frame {
    /// Anything larger is treated as a corrupt stream, not buffered.
    public static let maxPayloadLength = 1024

    public static func encode(_ message: Message) -> [UInt8] {
        let payload = message.encoded()
        let length = UInt32(payload.count)
        var out: [UInt8] = []
        out.reserveCapacity(4 + payload.count)
        for shift in stride(from: 24, through: 0, by: -8) {
            out.append(UInt8(truncatingIfNeeded: length >> UInt32(shift)))
        }
        out.append(contentsOf: payload)
        return out
    }
}

/// Reassembles messages from an arbitrary chunking of the TCP byte stream.
///
/// After `next()` throws, the stream is desynchronized: drop the connection.
public struct FrameDecoder: Sendable {
    private var buffer: [UInt8] = []
    private var readIndex = 0

    public init() {}

    public mutating func append(_ bytes: [UInt8]) {
        buffer.append(contentsOf: bytes)
    }

    /// Returns the next complete message, or `nil` if more bytes are needed.
    public mutating func next() throws(WireError) -> Message? {
        let available = buffer.count - readIndex
        guard available >= 4 else { return needMoreBytes() }

        var length = 0
        for i in 0..<4 { length = (length << 8) | Int(buffer[readIndex + i]) }
        guard length > 0 else { throw .emptyFrame }
        guard length <= Frame.maxPayloadLength else { throw .frameTooLarge(length) }
        guard available >= 4 + length else { return needMoreBytes() }

        let start = readIndex + 4
        let payload = Array(buffer[start..<(start + length)])
        readIndex = start + length
        if readIndex == buffer.count {
            buffer.removeAll(keepingCapacity: true)
            readIndex = 0
        }
        return try Message(payload: payload)
    }

    private mutating func needMoreBytes() -> Message? {
        if readIndex > 0 {
            buffer.removeFirst(readIndex)
            readIndex = 0
        }
        return nil
    }
}
