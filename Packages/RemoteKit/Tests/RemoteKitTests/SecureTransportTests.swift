import Foundation
import Network
import Testing
@testable import RemoteKit

/// A real TLS-PSK listener on loopback, answering `ping` with `pong`. Counts connections
/// that completed the TLS handshake so tests can assert a rejected peer never got that far.
private final class EchoServer: @unchecked Sendable {
    private let lock = NSLock()
    private var handshakes = 0
    private var live: [NWConnection] = []
    let listener: NWListener
    let queue = DispatchQueue(label: "EchoServer")

    var handshakeCount: Int { lock.withLock { handshakes } }
    var port: UInt16 { listener.port!.rawValue }

    init(credentials: [PairingCredential]) async throws {
        listener = try NWListener(using: SecureTransport.serverParameters(credentials: credentials), on: .any)
        listener.newConnectionHandler = { [unowned self] connection in
            lock.withLock { live.append(connection) }
            connection.stateUpdateHandler = { [unowned self] state in
                if case .ready = state {
                    lock.withLock { handshakes += 1 }
                    receive(on: connection, decoder: Box())
                }
            }
            connection.start(queue: queue)
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = Once()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: if once.take() { continuation.resume() }
                case .failed(let error): if once.take() { continuation.resume(throwing: error) }
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    final class Box: @unchecked Sendable { var decoder = FrameDecoder() }

    private func receive(on connection: NWConnection, decoder box: Box) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [unowned self] data, _, isComplete, error in
            if let data {
                box.decoder.append([UInt8](data))
                while let message = try? box.decoder.next() {
                    if case .ping(let timestamp) = message {
                        connection.send(content: Data(Frame.encode(.pong(timestamp: timestamp))), completion: .contentProcessed { _ in })
                    }
                }
            }
            if error == nil && !isComplete { receive(on: connection, decoder: box) }
        }
    }

    func stop() {
        listener.cancel()
        lock.withLock { live }.forEach { $0.cancel() }
    }
}

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var taken = false
    func take() -> Bool { lock.withLock { defer { taken = true }; return !taken } }
}

private enum Outcome: Equatable {
    case roundTrip   // handshake done and an encrypted ping/pong completed
    case rejected    // connection failed or was closed before a pong
    case timeout
}

/// Connects with `parameters`, sends a ping, and waits for the pong.
private func attempt(port: UInt16, parameters: NWParameters, timeout: TimeInterval = 4, host: String = "127.0.0.1") async -> Outcome {
    let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: parameters)
    let queue = DispatchQueue(label: "client")
    return await withCheckedContinuation { continuation in
        let once = Once()
        let finish: @Sendable (Outcome) -> Void = { outcome in
            if once.take() {
                connection.cancel()
                continuation.resume(returning: outcome)
            }
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: Data(Frame.encode(.ping(timestamp: 7))), completion: .contentProcessed { _ in })
                connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, isComplete, error in
                    if let data, !data.isEmpty {
                        var decoder = FrameDecoder()
                        decoder.append([UInt8](data))
                        if (try? decoder.next()) == .pong(timestamp: 7) { finish(.roundTrip); return }
                    }
                    if error != nil || isComplete { finish(.rejected) }
                }
            case .failed, .cancelled:
                finish(.rejected)
            case .waiting:
                // A failed PSK handshake surfaces as `.waiting(.tls(-9820 bad MAC / -9864 unknown PSK identity))`.
                finish(.rejected)
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + timeout) { finish(.timeout) }
    }
}

@Suite(.serialized) struct SecureTransportTests {
    private func credential() -> PairingCredential {
        PairingCredential(pairingID: UUID(), key: PairingInvite.randomKey())
    }

    @Test func matchingKeyCompletesAnEncryptedRoundTrip() async throws {
        let paired = credential()
        let server = try await EchoServer(credentials: [paired])
        defer { server.stop() }
        let outcome = await attempt(port: server.port, parameters: SecureTransport.clientParameters(credential: paired))
        #expect(outcome == .roundTrip)
        #expect(server.handshakeCount == 1)
    }

    @Test func wrongKeyWithKnownIdentityIsRejected() async throws {
        let paired = credential()
        let server = try await EchoServer(credentials: [paired])
        defer { server.stop() }
        let forged = PairingCredential(pairingID: paired.pairingID, key: PairingInvite.randomKey())
        let outcome = await attempt(port: server.port, parameters: SecureTransport.clientParameters(credential: forged))
        #expect(outcome == .rejected)
        #expect(server.handshakeCount == 0)
    }

    /// Regression: with TLS session resumption on, a wrong key rode on a session cached from an
    /// earlier good connection to the same endpoint and was accepted without any PSK check.
    @Test func wrongKeyCannotRideACachedSession() async throws {
        let paired = credential()
        let server = try await EchoServer(credentials: [paired])
        defer { server.stop() }
        let good = await attempt(port: server.port, parameters: SecureTransport.clientParameters(credential: paired), host: "localhost")
        #expect(good == .roundTrip)

        let forged = PairingCredential(pairingID: paired.pairingID, key: PairingInvite.randomKey())
        let bad = await attempt(port: server.port, parameters: SecureTransport.clientParameters(credential: forged), host: "localhost")
        #expect(bad == .rejected)
        #expect(server.handshakeCount == 1) // only the good connection ever completed a handshake

        // And the right key still works afterwards.
        let again = await attempt(port: server.port, parameters: SecureTransport.clientParameters(credential: paired), host: "localhost")
        #expect(again == .roundTrip)
    }

    @Test func forgottenPairingCannotReconnectOnACachedSession() async throws {
        let paired = credential()
        let first = try await EchoServer(credentials: [paired])
        #expect(await attempt(port: first.port, parameters: SecureTransport.clientParameters(credential: paired), host: "localhost") == .roundTrip)
        first.stop()

        // The Mac "forgets" the phone: a new listener without its key.
        let second = try await EchoServer(credentials: [credential()])
        defer { second.stop() }
        let outcome = await attempt(port: second.port, parameters: SecureTransport.clientParameters(credential: paired), host: "localhost")
        #expect(outcome == .rejected)
        #expect(second.handshakeCount == 0)
    }

    @Test func unknownIdentityIsRejected() async throws {
        let server = try await EchoServer(credentials: [credential()])
        defer { server.stop() }
        let outcome = await attempt(port: server.port, parameters: SecureTransport.clientParameters(credential: credential()))
        #expect(outcome == .rejected)
        #expect(server.handshakeCount == 0)
    }

    @Test func plaintextClientCannotTalkToTheListener() async throws {
        let server = try await EchoServer(credentials: [credential()])
        defer { server.stop() }
        let outcome = await attempt(port: server.port, parameters: NWParameters(tls: nil, tcp: Service.makeTCPOptions()), timeout: 2)
        // It may be refused or simply never serviced; what matters is it never gets a reply.
        #expect(outcome != .roundTrip)
        #expect(server.handshakeCount == 0)
    }

    @Test func listenerServesSeveralPairedPhonesByIdentity() async throws {
        let a = credential(), b = credential(), outsider = credential()
        let server = try await EchoServer(credentials: [a, b])
        defer { server.stop() }
        #expect(await attempt(port: server.port, parameters: SecureTransport.clientParameters(credential: a)) == .roundTrip)
        #expect(await attempt(port: server.port, parameters: SecureTransport.clientParameters(credential: b)) == .roundTrip)
        #expect(await attempt(port: server.port, parameters: SecureTransport.clientParameters(credential: outsider)) == .rejected)
        #expect(server.handshakeCount == 2)
    }

    @Test func listenerWithNoCredentialsRejectsEveryone() async throws {
        let server = try await EchoServer(credentials: [])
        defer { server.stop() }
        let outcome = await attempt(port: server.port, parameters: SecureTransport.clientParameters(credential: credential()))
        #expect(outcome == .rejected)
        #expect(server.handshakeCount == 0)
    }
}
