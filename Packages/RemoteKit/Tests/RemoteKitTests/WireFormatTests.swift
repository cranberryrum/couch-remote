import Testing
@testable import RemoteKit

private let samples: [Message] = [
    .hello(name: "Aditya's iPhone"),
    .hello(name: ""),
    .move(dx: 3.5, dy: -12.25),
    .move(dx: 0, dy: 0),
    .button(.left, .down),
    .button(.right, .up),
    .click(.left, count: 1),
    .click(.left, count: 2),
    .click(.right, count: 1),
    .scroll(dx: 0, dy: -40.5, phase: .began),
    .scroll(dx: 1, dy: 2, phase: .changed),
    .scroll(dx: 0, dy: 0, phase: .ended),
    .scroll(dx: 0, dy: 9, phase: .momentumBegan),
    .scroll(dx: 0, dy: 3, phase: .momentumChanged),
    .scroll(dx: 0, dy: 0, phase: .momentumEnded),
    .media(.playPause), .media(.next), .media(.previous), .media(.volumeUp), .media(.volumeDown),
    .key(.arrowLeft), .key(.arrowRight), .key(.space),
    .ping(timestamp: 0),
    .ping(timestamp: UInt64.max),
    .pong(timestamp: 0x0102_0304_0506_0708),
]

@Suite struct WireFormatTests {
    @Test(arguments: samples)
    func payloadRoundTrips(message: Message) throws {
        #expect(try Message(payload: message.encoded()) == message)
    }

    @Test(arguments: samples)
    func frameRoundTrips(message: Message) throws {
        var decoder = FrameDecoder()
        decoder.append(Frame.encode(message))
        #expect(try decoder.next() == message)
        #expect(try decoder.next() == nil)
    }

    @Test func moveFrameIsCompact() {
        // 4-byte length + tag + 2 × f32
        #expect(Frame.encode(.move(dx: 1, dy: 2)).count == 13)
    }

    @Test func framesAreBigEndianLengthPrefixed() {
        #expect(Frame.encode(.media(.next)) == [0, 0, 0, 2, 0x05, 0x01])
    }

    @Test func decoderHandlesByteAtATimeDelivery() throws {
        let stream = samples.flatMap { Frame.encode($0) }
        var decoder = FrameDecoder()
        var decoded: [Message] = []
        for byte in stream {
            decoder.append([byte])
            while let message = try decoder.next() { decoded.append(message) }
        }
        #expect(decoded == samples)
    }

    @Test func decoderHandlesManyFramesInOneChunk() throws {
        var decoder = FrameDecoder()
        decoder.append(samples.flatMap { Frame.encode($0) })
        var decoded: [Message] = []
        while let message = try decoder.next() { decoded.append(message) }
        #expect(decoded == samples)
    }

    @Test func decoderKeepsPartialFrameUntilCompleted() throws {
        let frame = Frame.encode(.ping(timestamp: 42))
        var decoder = FrameDecoder()
        decoder.append(Array(frame.prefix(6)))
        #expect(try decoder.next() == nil)
        decoder.append(Array(frame.dropFirst(6)))
        #expect(try decoder.next() == .ping(timestamp: 42))
    }

    @Test func unknownTagThrows() {
        #expect(throws: WireError.unknownTag(0x7F)) { try Message(payload: [0x7F]) }
    }

    @Test func invalidEnumValueThrows() {
        #expect(throws: WireError.invalidValue) { try Message(payload: [0x05, 0xEE]) }
    }

    @Test func truncatedPayloadThrows() {
        #expect(throws: WireError.truncated) { try Message(payload: [0x01, 0, 0]) }
        #expect(throws: WireError.truncated) { try Message(payload: []) }
    }

    @Test func trailingBytesThrow() {
        #expect(throws: WireError.trailingBytes) { try Message(payload: [0x05, 0x00, 0x00]) }
    }

    @Test func oversizedFrameThrows() {
        var decoder = FrameDecoder()
        decoder.append([0x00, 0x00, 0xFF, 0xFF])
        #expect(throws: WireError.frameTooLarge(0xFFFF)) { try decoder.next() }
    }

    @Test func zeroLengthFrameThrows() {
        var decoder = FrameDecoder()
        decoder.append([0, 0, 0, 0])
        #expect(throws: WireError.emptyFrame) { try decoder.next() }
    }

    @Test func longNamesAreTruncated() throws {
        let long = String(repeating: "x", count: 500)
        let decoded = try Message(payload: Message.hello(name: long).encoded())
        #expect(decoded == .hello(name: String(repeating: "x", count: Message.maxNameLength)))
    }
}
