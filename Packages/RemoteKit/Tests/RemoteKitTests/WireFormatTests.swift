import Foundation
import Testing
@testable import RemoteKit

private let deviceID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
private let pairingID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
private let macID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
private let proof = (0..<32).map { UInt8($0) }

private let samples: [Message] = [
    .hello(protocolVersion: Message.protocolVersion, deviceID: deviceID, pairingID: pairingID, name: "Aditya's iPhone", proof: proof),
    .hello(protocolVersion: Message.protocolVersion, deviceID: deviceID, pairingID: pairingID, name: "", proof: proof),
    .welcome(protocolVersion: Message.protocolVersion, macID: macID, name: "Work MacBook 💼"),
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
    .key(.return), .key(.backspace), .key(.escape), .key(.tab, modifiers: [.control, .shift]),
    .key(.arrowUp), .key(.arrowDown), .key(.f), .key(.t, modifiers: .command),
    .key(.w, modifiers: [.command, .shift, .control, .option]),
    .text("hello"), .text("émoji 👨‍👩‍👧‍👦 日本語"), .text(""),
    .sleepTimer(minutes: 0), .sleepTimer(minutes: 45), .sleepTimer(minutes: .max),
    .macStatus(MacStatus()), .macStatus(MacStatus(sleepTimerRemaining: 0)),
    .macStatus(MacStatus(sleepTimerRemaining: 5400)),
    .disconnect(.userRequested), .disconnect(.replaced), .disconnect(.forgotten),
    .disconnect(.serverStopped), .disconnect(.macSleeping), .disconnect(.versionMismatch),
    .disconnect(.unauthorized),
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

    // MARK: Stability of the stage-1 wire format

    @Test func stage1RawValuesAreUnchanged() {
        #expect(KeyCode.arrowLeft.rawValue == 0 && KeyCode.arrowRight.rawValue == 1 && KeyCode.space.rawValue == 2)
        #expect(MediaKey.playPause.rawValue == 0 && MediaKey.volumeDown.rawValue == 4)
        #expect(ScrollPhase.began.rawValue == 0 && ScrollPhase.momentumEnded.rawValue == 5)
        #expect(MouseButton.left.rawValue == 0 && MouseButton.right.rawValue == 1)
        #expect(ButtonState.up.rawValue == 0 && ButtonState.down.rawValue == 1)
    }

    @Test func stage1KeyPayloadWithoutModifiersStillDecodes() throws {
        #expect(try Message(payload: [0x06, 0x01]) == .key(.arrowRight, modifiers: []))
    }

    // MARK: Version handshake

    @Test func helloWithOtherVersionDecodesLeniently() throws {
        // A future layout: version byte followed by something we don't understand.
        let decoded = try Message(payload: [0x00, 99, 1, 2, 3, 4, 5])
        #expect(decoded == .hello(protocolVersion: 99, deviceID: .zero, pairingID: .zero, name: "", proof: []))
    }

    @Test func welcomeWithOtherVersionDecodesLeniently() throws {
        let decoded = try Message(payload: [0x09, 1])
        #expect(decoded == .welcome(protocolVersion: 1, macID: .zero, name: ""))
    }

    // MARK: macStatus is extensible

    @Test func macStatusSkipsUnknownEntries() throws {
        // count 2: unknown key 9 (2 bytes), then key 1 = 600 s
        let payload: [UInt8] = [0x0A, 2, 9, 2, 0xAA, 0xBB, 1, 4, 0, 0, 0x02, 0x58]
        #expect(try Message(payload: payload) == .macStatus(MacStatus(sleepTimerRemaining: 600)))
    }

    @Test func macStatusWithBadKnownLengthThrows() {
        #expect(throws: WireError.invalidValue) { try Message(payload: [0x0A, 1, 1, 2, 0, 0]) }
    }

    // MARK: Text chunking

    @Test func textChunksRejoinExactlyAndFitTheLimit() {
        let text = String(repeating: "héllo 👨‍👩‍👧‍👦 日本語 ", count: 60)
        let chunks = Message.textMessages(for: text)
        #expect(chunks.count > 1)
        var joined = ""
        for case .text(let part) in chunks {
            #expect(part.utf8.count <= Message.maxTextBytes)
            joined += part
        }
        #expect(joined == text)
    }

    @Test func textChunksNeverFrameOverflow() {
        let text = String(repeating: "👨‍👩‍👧‍👦", count: 100)
        for message in Message.textMessages(for: text) {
            #expect(Frame.encode(message).count <= 4 + Frame.maxPayloadLength)
        }
    }

    @Test func emptyTextProducesNoMessages() {
        #expect(Message.textMessages(for: "").isEmpty)
    }

    // MARK: Streaming

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

    // MARK: Malformed input

    @Test func unknownTagThrows() {
        #expect(throws: WireError.unknownTag(0x7F)) { try Message(payload: [0x7F]) }
    }

    @Test func invalidEnumValueThrows() {
        #expect(throws: WireError.invalidValue) { try Message(payload: [0x05, 0xEE]) }
        #expect(throws: WireError.invalidValue) { try Message(payload: [0x0D, 0xEE]) }
    }

    @Test func truncatedPayloadThrows() {
        #expect(throws: WireError.truncated) { try Message(payload: [0x01, 0, 0]) }
        #expect(throws: WireError.truncated) { try Message(payload: []) }
        #expect(throws: WireError.truncated) { try Message(payload: [0x00, Message.protocolVersion, 1, 2, 3]) }
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
        let decoded = try Message(payload: Message.welcome(protocolVersion: Message.protocolVersion, macID: macID, name: long).encoded())
        guard case .welcome(_, _, let name) = decoded else {
            Issue.record("expected welcome")
            return
        }
        #expect(name.utf8.count <= Message.maxNameLength * 4)
        #expect(!name.isEmpty)
    }
}
