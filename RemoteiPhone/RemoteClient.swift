import Network
import Observation
import OSLog
import RemoteKit
import UIKit

/// Keeps the list of paired Macs, watches Bonjour to see which are online, and runs at most one
/// connection at a time. **Connecting is always manual**: nothing connects on launch or on
/// discovery. The only automatic connects are *resuming* the Mac you were already using
/// (after a Wi-Fi blip, or returning from the background) and connecting right after you pair.
@Observable
final class RemoteClient {
    enum Phase: Equatable {
        case idle                // showing "My Macs"
        case connecting(UUID)    // you asked to connect; waiting for TLS + welcome
        case connected(UUID)
        case reconnecting(UUID)  // the link dropped; retrying the same Mac for a short window
    }

    private(set) var phase: Phase = .idle
    private(set) var pairedMacs: [PairedMac]
    private(set) var onlineMacIDs: Set<UUID> = []
    private(set) var rttMs: Double?
    private(set) var macStatus: MacStatus?
    private(set) var localNetworkDenied = false
    /// One-line message for the My Macs screen (why we ended up there, what to do).
    var notice: String?

    var isConnected: Bool {
        if case .connected = phase { return true }
        return false
    }

    /// The Mac this phase is about, if any.
    var activeMac: PairedMac? {
        switch phase {
        case .idle: nil
        case .connecting(let id), .connected(let id), .reconnecting(let id): mac(id)
        }
    }

    func mac(_ id: UUID) -> PairedMac? { pairedMacs.first { $0.macID == id } }
    func isOnline(_ id: UUID) -> Bool { onlineMacIDs.contains(id) }

    /// Seconds left on the Mac's sleep timer, counting down locally between the Mac's updates.
    func sleepTimerRemaining(at date: Date) -> Int? {
        guard let base = macStatus?.sleepTimerRemaining, let received = macStatusReceivedAt else { return nil }
        return max(0, base - Int(date.timeIntervalSince(received)))
    }

    let deviceID: UUID

    @ObservationIgnored private let secrets: SecretStore
    @ObservationIgnored private var macStatusReceivedAt: Date?
    @ObservationIgnored private var endpoints: [UUID: NWEndpoint] = [:]
    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var connection: NWConnection?
    @ObservationIgnored private var decoder = FrameDecoder()
    @ObservationIgnored private var attemptTask: Task<Void, Never>?
    @ObservationIgnored private var attemptTimeout: Task<Void, Never>?
    @ObservationIgnored private var pingTask: Task<Void, Never>?
    @ObservationIgnored private var retryDeadline: Date?
    @ObservationIgnored private var resumeTarget: UUID?
    @ObservationIgnored private var lastPong: UInt64 = 0
    @ObservationIgnored private let log = Logger(subsystem: "com.adityakolte.couchremote.ios", category: "client")

    private static let deviceIDAccount = "deviceID"
    private static let macsAccount = "pairedMacs"
    private static let pongTimeout: UInt64 = 4_000_000_000

    private static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

    init(secrets: SecretStore = KeychainSecretStore(service: "com.adityakolte.couchremote.ios")) {
        self.secrets = secrets
        if let data = secrets.read(Self.deviceIDAccount),
           let string = String(data: data, encoding: .utf8),
           let id = UUID(uuidString: string) {
            deviceID = id
        } else {
            let id = UUID()
            try? secrets.write(Data(id.uuidString.utf8), account: Self.deviceIDAccount)
            deviceID = id
        }
        pairedMacs = secrets.read(Self.macsAccount)
            .flatMap { try? JSONDecoder().decode([PairedMac].self, from: $0) } ?? []
    }

    // MARK: App lifecycle

    /// Foreground: watch Bonjour, and resume the Mac we were using when we left (if any).
    func start() {
        startBrowsing()
        if let id = resumeTarget {
            resumeTarget = nil
            begin(id, window: Tuning.reconnectWindow, resuming: true)
        }
    }

    /// Background: drop the link (so the Mac releases its keep-awake hold) but remember the Mac.
    func stop() {
        switch phase {
        case .idle:
            resumeTarget = nil
        case .connecting(let id), .connected(let id), .reconnecting(let id):
            resumeTarget = id
        }
        dropConnection()
        retryDeadline = nil
        phase = resumeTarget.map { .reconnecting($0) } ?? .idle
        stopBrowsing()
    }

    // MARK: Actions

    /// Manual connect: one attempt, no retries. Failure returns to My Macs with a notice.
    func connect(_ id: UUID) {
        begin(id, window: 0, resuming: false)
    }

    /// Manual disconnect: back to My Macs, and stay there.
    func disconnect() {
        dropConnection()
        retryDeadline = nil
        resumeTarget = nil
        phase = .idle
    }

    func handle(url: URL) {
        guard let invite = PairingInvite(url: url) else {
            notice = "That link isn't a CouchRemote pairing code."
            return
        }
        pair(invite)
    }

    /// Stores the pairing, then connects once: pairing is only complete after the Mac has
    /// verified this phone's first `hello`, and the invite expires after 5 minutes.
    func pair(_ invite: PairingInvite) {
        var mac = PairedMac(invite: invite)
        if let existing = self.mac(invite.macID) {
            mac.customName = existing.customName
            pairedMacs.removeAll { $0.macID == invite.macID }
        }
        pairedMacs.append(mac)
        persist()
        begin(invite.macID, window: Tuning.pairConnectWindow, resuming: false)
    }

    func forget(_ id: UUID) {
        if activeMac?.macID == id { disconnect() }
        pairedMacs.removeAll { $0.macID == id }
        persist()
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = pairedMacs.firstIndex(where: { $0.macID == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        pairedMacs[index].customName = trimmed.isEmpty ? nil : trimmed
        persist()
    }

    func setSleepTimer(minutes: Int) {
        send(.sleepTimer(minutes: UInt16(clamping: minutes)))
    }

    func cancelSleepTimer() {
        send(.sleepTimer(minutes: 0))
    }

    func send(_ message: Message) {
        guard isConnected, let connection else { return }
        connection.send(content: Data(Frame.encode(message)), completion: .contentProcessed { _ in })
    }

    private func persist() {
        do {
            try secrets.write(try JSONEncoder().encode(pairedMacs), account: Self.macsAccount)
        } catch {
            log.error("Could not store paired Macs: \(String(describing: error))")
            notice = "Couldn't save to the Keychain."
        }
    }

    // MARK: Discovery

    private func startBrowsing() {
        guard browser == nil else { return }
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: Service.type, domain: nil),
            using: Service.makeBrowseParameters()
        )
        // All Network callbacks are delivered on the main queue (`start(queue: .main)`).
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated { self?.browseResultsChanged(results) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.browserStateChanged(state) }
        }
        self.browser = browser
        browser.start(queue: .main)
    }

    private func stopBrowsing() {
        browser?.cancel()
        browser = nil
        endpoints = [:]
        onlineMacIDs = []
    }

    private func browserStateChanged(_ state: NWBrowser.State) {
        switch state {
        case .ready:
            localNetworkDenied = false
        case .waiting(let error), .failed(let error):
            // kDNSServiceErr_PolicyDenied: what Network reports when Local Network access is refused.
            if case .dns(let code) = error, code == -65570 {
                localNetworkDenied = true
            } else {
                log.error("Browser: \(error.localizedDescription)")
            }
        default:
            break
        }
    }

    private func browseResultsChanged(_ results: Set<NWBrowser.Result>) {
        // A Mac is identified by the macID in its TXT record, never by name. The same Mac can
        // appear once per interface (Wi-Fi, peer-to-peer); keep one, preferring Wi-Fi/Ethernet.
        var best: [UUID: (endpoint: NWEndpoint, rank: Int)] = [:]
        for result in results {
            guard case .bonjour(let record) = result.metadata,
                  let idString = record[Service.txtMacID],
                  let id = UUID(uuidString: idString)
            else { continue }
            let rank = result.interfaces.contains { $0.type == .wifi || $0.type == .wiredEthernet } ? 0 : 1
            if let existing = best[id], existing.rank <= rank { continue }
            best[id] = (result.endpoint, rank)
        }
        endpoints = best.mapValues(\.endpoint)
        onlineMacIDs = Set(best.keys)
    }

    // MARK: Connecting

    private func targetIsActive(_ id: UUID) -> Bool {
        switch phase {
        case .connecting(let active), .reconnecting(let active): active == id
        case .idle, .connected: false
        }
    }

    /// `window` > 0 keeps retrying until the deadline (resume, or just-paired); 0 = one try.
    private func begin(_ id: UUID, window: TimeInterval, resuming: Bool) {
        guard mac(id) != nil else { return }
        dropConnection()
        notice = nil
        resumeTarget = nil
        retryDeadline = window > 0 ? Date().addingTimeInterval(window) : nil
        phase = resuming ? .reconnecting(id) : .connecting(id)
        attempt(id)
    }

    private func scheduleAttempt(_ id: UUID, after delay: Duration) {
        attemptTask?.cancel()
        attemptTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.attempt(id)
        }
    }

    private func attempt(_ id: UUID) {
        guard targetIsActive(id), connection == nil, let mac = mac(id) else { return }

        guard let endpoint = endpoints[id] else {
            // Not seen on Bonjour (yet). Keep waiting if we're inside a retry window.
            if let deadline = retryDeadline, Date() < deadline {
                scheduleAttempt(id, after: .milliseconds(500))
            } else if case .reconnecting = phase {
                fail("Lost connection to \(mac.displayName). Is it still running, on the same Wi-Fi?")
            } else {
                fail("\(mac.displayName) isn't reachable. Is CouchRemote running on it, on the same Wi-Fi?")
            }
            return
        }

        let connection = NWConnection(to: endpoint, using: SecureTransport.clientParameters(credential: mac.credential))
        self.connection = connection
        decoder = FrameDecoder()
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            MainActor.assumeIsolated {
                guard let self, let connection, connection === self.connection else { return }
                self.connectionStateChanged(state, macID: id)
            }
        }
        connection.start(queue: .main)

        attemptTimeout = Task { [weak self, weak connection] in
            try? await Task.sleep(for: .seconds(Tuning.connectAttemptTimeout))
            guard !Task.isCancelled, let self, let connection, connection === self.connection else { return }
            self.connectionEnded(id, tlsRejected: false)
        }
    }

    private func connectionStateChanged(_ state: NWConnection.State, macID: UUID) {
        switch state {
        case .ready:
            // TLS-PSK handshake succeeded. Prove which pairing we are, then wait for `welcome`.
            guard let mac = mac(macID) else { return }
            let proof = HelloProof.make(key: mac.key, deviceID: deviceID, pairingID: mac.pairingID)
            send(helloMessage: .hello(
                protocolVersion: Message.protocolVersion,
                deviceID: deviceID,
                pairingID: mac.pairingID,
                name: UIDevice.current.name,
                proof: proof
            ))
            receive(macID: macID)
        case .waiting(let error):
            // A failed PSK handshake (wrong key / unknown identity) shows up here, not as .failed.
            if case .tls = error { connectionEnded(macID, tlsRejected: true) }
        case .failed(let error):
            if case .tls = error {
                connectionEnded(macID, tlsRejected: true)
            } else {
                connectionEnded(macID, tlsRejected: false)
            }
        default:
            break
        }
    }

    /// `hello` goes out before `isConnected` is true, so it bypasses `send`.
    private func send(helloMessage: Message) {
        connection?.send(content: Data(Frame.encode(helloMessage)), completion: .contentProcessed { _ in })
    }

    private func receive(macID: UUID) {
        guard let connection else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 2048) { [weak self, weak connection] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self, let connection, connection === self.connection else { return }
                if let data {
                    self.decoder.append([UInt8](data))
                    self.drain(macID: macID)
                    guard connection === self.connection else { return }
                }
                if error != nil || isComplete {
                    self.connectionEnded(macID, tlsRejected: false)
                    return
                }
                self.receive(macID: macID)
            }
        }
    }

    private func drain(macID: UUID) {
        while connection != nil {
            do {
                guard let message = try decoder.next() else { return }
                handle(message, macID: macID)
            } catch {
                log.error("Protocol error: \(String(describing: error))")
                connectionEnded(macID, tlsRejected: false)
                return
            }
        }
    }

    private func handle(_ message: Message, macID: UUID) {
        switch message {
        case .welcome(let version, let welcomedID, let name):
            guard version == Message.protocolVersion else {
                fail("Update the other app: the Mac and the iPhone app speak different versions.")
                return
            }
            guard welcomedID == macID else {
                fail("That isn't the Mac you paired with.")
                return
            }
            attemptTimeout?.cancel()
            if let index = pairedMacs.firstIndex(where: { $0.macID == macID }), pairedMacs[index].macName != name, !name.isEmpty {
                pairedMacs[index].macName = name
                persist()
            }
            retryDeadline = nil
            notice = nil
            phase = .connected(macID)
            startPinging(macID)
        case .pong(let timestamp):
            let now = Self.now()
            lastPong = now
            rttMs = Double(now &- timestamp) / 1_000_000
        case .macStatus(let status):
            macStatus = status
            macStatusReceivedAt = Date()
        case .disconnect(let reason):
            fail(Self.notice(for: reason))
        default:
            break
        }
    }

    private static func notice(for reason: DisconnectReason) -> String {
        switch reason {
        case .userRequested: "The Mac disconnected this iPhone."
        case .replaced: "Another iPhone took over this Mac."
        case .forgotten: "This Mac forgot this iPhone. Forget it here and pair again."
        case .serverStopped: "The Mac stopped accepting connections."
        case .macSleeping: "The Mac went to sleep."
        case .versionMismatch: "Update the other app: the Mac and the iPhone app speak different versions."
        case .unauthorized: "The Mac didn't accept this iPhone. Forget it here and pair again."
        }
    }

    private func startPinging(_ id: UUID) {
        pingTask?.cancel()
        lastPong = Self.now()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if Self.now() - self.lastPong > Self.pongTimeout {
                    self.connectionEnded(id, tlsRejected: false)
                    return
                }
                self.send(.ping(timestamp: Self.now()))
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: Ending

    /// The link ended without the Mac telling us why (network drop, timeout, handshake failure).
    private func connectionEnded(_ id: UUID, tlsRejected: Bool) {
        guard targetIsActive(id) || phase == .connected(id) else { return }
        let wasConnected = phase == .connected(id)
        let name = mac(id)?.displayName ?? "the Mac"
        dropConnection()

        if tlsRejected {
            fail("\(name) didn't accept this iPhone. If you forgot it on the Mac, forget it here and pair again.")
        } else if wasConnected {
            // Unexpected drop: retry the same Mac for a short window, then give up.
            retryDeadline = Date().addingTimeInterval(Tuning.reconnectWindow)
            phase = .reconnecting(id)
            scheduleAttempt(id, after: .milliseconds(300))
        } else if let deadline = retryDeadline, Date() < deadline {
            scheduleAttempt(id, after: .seconds(1))
        } else if case .reconnecting = phase {
            fail("Lost connection to \(name).")
        } else {
            // An unknown PSK identity (the Mac forgot this iPhone) can look like a plain timeout.
            fail("Couldn't connect to \(name). If you removed this iPhone on the Mac, forget the Mac here and pair again.")
        }
    }

    /// Ends everything and returns to My Macs with `message`.
    private func fail(_ message: String) {
        dropConnection()
        retryDeadline = nil
        resumeTarget = nil
        phase = .idle
        notice = message
    }

    private func dropConnection() {
        attemptTask?.cancel()
        attemptTask = nil
        attemptTimeout?.cancel()
        attemptTimeout = nil
        pingTask?.cancel()
        pingTask = nil
        let old = connection
        connection = nil // detach first so the cancel callback is ignored
        old?.cancel()
        decoder = FrameDecoder()
        rttMs = nil
        macStatus = nil
        macStatusReceivedAt = nil
    }
}
