import AppKit
import Network
import Observation
import OSLog
import RemoteKit

/// Listens for paired phones over TLS-PSK, advertises over Bonjour, and feeds messages to the injector.
///
/// A connection is trusted in two steps: the TLS-PSK handshake (the peer holds *some* paired key),
/// then a `hello` whose proof ties it to one specific pairing. Only then does it become the active
/// session and replace any previous one, so a failed or merely half-open connection can never
/// kick out the phone you're using. One phone at a time.
@Observable
final class RemoteServer {
    private(set) var isListening = false
    private(set) var isAccepting: Bool
    private(set) var connectedPhone: PairedPhone?
    /// A short-lived message for the menu, e.g. a version mismatch.
    private(set) var notice: String?

    var isClientConnected: Bool { connectedPhone != nil }

    @ObservationIgnored let pairing: PairingStore
    @ObservationIgnored let sleepTimer: SleepTimer
    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var active: Session?
    @ObservationIgnored private var unauthenticated: [ObjectIdentifier: Session] = [:]
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var ticks = 0
    @ObservationIgnored private let injector = InputInjector()
    @ObservationIgnored private let keepAwake = KeepAwake()
    @ObservationIgnored private let log = Logger(subsystem: "com.adityakolte.couchremote.mac", category: "server")

    private static let acceptingKey = "acceptConnections"
    private static let maxUnauthenticated = 4
    private static let helloTimeout: Duration = .seconds(5)

    private final class Session {
        let connection: NWConnection
        var decoder = FrameDecoder()
        var phone: PairedPhone?
        var helloTimeout: Task<Void, Never>?

        init(_ connection: NWConnection) { self.connection = connection }

        func send(_ message: Message) {
            connection.send(content: Data(Frame.encode(message)), completion: .contentProcessed { _ in })
        }

        /// Sends `message`, then closes gracefully (FIN after the data) so the peer reliably
        /// receives it; a hard cancel after a send can drop the bytes.
        func sendAndClose(_ message: Message) {
            connection.send(
                content: Data(Frame.encode(message)),
                contentContext: .finalMessage,
                isComplete: true,
                completion: .contentProcessed { _ in }
            )
            let connection = connection
            Task {
                try? await Task.sleep(for: .seconds(1))
                connection.cancel()
            }
        }
    }

    init(pairing: PairingStore, sleepTimer: SleepTimer) {
        self.pairing = pairing
        self.sleepTimer = sleepTimer
        isAccepting = UserDefaults.standard.object(forKey: Self.acceptingKey) as? Bool ?? true
    }

    private var macName: String { Host.current().localizedName ?? "Mac" }

    // MARK: Control (menu / app)

    func start() {
        startListener()
        if wakeObserver == nil {
            // The listener can silently die across sleep; rebuild it on wake.
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshListener() }
            }
        }
    }

    func setAccepting(_ on: Bool) {
        guard on != isAccepting else { return }
        isAccepting = on
        UserDefaults.standard.set(on, forKey: Self.acceptingKey)
        if on {
            startListener()
        } else {
            // Off means off: stop advertising, stop listening, and drop the current phone.
            stopListener()
            disconnectActive(reason: .serverStopped)
            for session in unauthenticated.values { session.connection.cancel() }
            unauthenticated.removeAll()
        }
    }

    /// Opens a 5-minute pairing invite (turning "Accept connections" on if needed).
    @discardableResult
    func beginPairing() -> PairingInvite {
        if !isAccepting { setAccepting(true) }
        let invite = pairing.beginPairing(macName: macName)
        refreshListener() // the new key must be in the listener's PSK list
        return invite
    }

    func cancelPairing() {
        pairing.cancelPending()
        refreshListener()
    }

    func forgetPhone(_ pairingID: UUID) {
        guard pairing.forget(pairingID: pairingID) else { return }
        if active?.phone?.pairingID == pairingID { disconnectActive(reason: .forgotten) }
        refreshListener()
    }

    func disconnectActive(reason: DisconnectReason) {
        guard let session = active else { return }
        clearActive()
        session.sendAndClose(.disconnect(reason))
    }

    /// The sleep timer ran out: tell the phone, drop the keep-awake hold, then sleep the Mac.
    func sleepSystemNow() {
        disconnectActive(reason: .macSleeping)
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            SystemSleep.now()
        }
    }

    /// Called once a second by the app.
    func tick() {
        if pairing.expirePending() { refreshListener() }
        ticks += 1
        if sleepTimer.endDate != nil, ticks % 5 == 0 { pushStatus() }
    }

    func pushStatus() {
        active?.send(.macStatus(MacStatus(sleepTimerRemaining: sleepTimer.remainingSeconds())))
    }

    // MARK: Listener

    private func startListener() {
        guard isAccepting, listener == nil else { return }
        let parameters = SecureTransport.serverParameters(credentials: pairing.credentials())
        do {
            let listener = try NWListener(using: parameters)
            listener.service = NWListener.Service(
                name: macName,
                type: Service.type,
                domain: nil,
                txtRecord: Self.txtRecord([
                    (Service.txtMacID, pairing.macID.uuidString),
                    (Service.txtVersion, String(Message.protocolVersion)),
                ])
            )
            // All Network callbacks are delivered on the main queue (`start(queue: .main)`).
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                MainActor.assumeIsolated {
                    guard let self, let listener, listener === self.listener else { return }
                    self.listenerStateChanged(state)
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.accept(connection) }
            }
            self.listener = listener
            listener.start(queue: .main)
        } catch {
            log.error("Could not create listener: \(error.localizedDescription)")
            scheduleRestart()
        }
    }

    private func stopListener() {
        listener?.cancel()
        listener = nil
        isListening = false
    }

    /// Rebuilds the listener so its PSK list matches the current pairings. Established
    /// connections are unaffected.
    private func refreshListener() {
        guard isAccepting else { return }
        stopListener()
        startListener()
    }

    private func scheduleRestart() {
        Task {
            try? await Task.sleep(for: .seconds(2))
            refreshListener()
        }
    }

    private func listenerStateChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            isListening = true
            log.info("Listening")
        case .failed(let error):
            log.error("Listener failed: \(error.localizedDescription)")
            stopListener()
            scheduleRestart()
        default:
            isListening = false
        }
    }

    /// DNS-SD TXT data: a sequence of `[length][key=value]` entries.
    private static func txtRecord(_ entries: [(String, String)]) -> Data {
        var data = Data()
        for (key, value) in entries {
            let bytes = Array("\(key)=\(value)".utf8)
            data.append(UInt8(bytes.count))
            data.append(contentsOf: bytes)
        }
        return data
    }

    // MARK: Connections

    private func accept(_ connection: NWConnection) {
        guard unauthenticated.count < Self.maxUnauthenticated else {
            connection.cancel()
            return
        }
        let session = Session(connection)
        unauthenticated[ObjectIdentifier(session)] = session

        connection.stateUpdateHandler = { [weak self, weak session] state in
            MainActor.assumeIsolated {
                guard let self, let session else { return }
                switch state {
                case .failed, .cancelled: self.end(session)
                default: break
                }
            }
        }
        connection.start(queue: .main)
        receive(on: session)

        session.helloTimeout = Task { [weak self, weak session] in
            try? await Task.sleep(for: Self.helloTimeout)
            guard !Task.isCancelled, let self, let session, session.phone == nil else { return }
            self.end(session)
        }
    }

    private func isLive(_ session: Session) -> Bool {
        session === active || unauthenticated[ObjectIdentifier(session)] != nil
    }

    private func end(_ session: Session) {
        session.helloTimeout?.cancel()
        unauthenticated[ObjectIdentifier(session)] = nil
        session.connection.cancel()
        if session === active { clearActive() }
    }

    private func clearActive() {
        active = nil
        connectedPhone = nil
        keepAwake.release()
        injector.releaseAll()
    }

    private func receive(on session: Session) {
        session.connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self, weak session] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self, let session, self.isLive(session) else { return }
                if let data {
                    session.decoder.append([UInt8](data))
                    self.drain(session)
                    guard self.isLive(session) else { return }
                }
                if error != nil || isComplete {
                    self.end(session)
                    return
                }
                self.receive(on: session)
            }
        }
    }

    private func drain(_ session: Session) {
        while isLive(session) {
            do {
                guard let message = try session.decoder.next() else { return }
                handle(message, from: session)
            } catch {
                log.error("Protocol error, dropping client: \(String(describing: error))")
                end(session)
                return
            }
        }
    }

    private func handle(_ message: Message, from session: Session) {
        // Until `hello` is verified, nothing else is accepted.
        guard session.phone != nil else {
            guard case .hello(let version, let deviceID, let pairingID, let name, let proof) = message else {
                end(session)
                return
            }
            authenticate(session, version: version, deviceID: deviceID, pairingID: pairingID, name: name, proof: proof)
            return
        }
        guard session === active else { return }

        switch message {
        case .ping(let timestamp):
            session.send(.pong(timestamp: timestamp))
        case .sleepTimer(let minutes):
            if minutes == 0 { sleepTimer.cancel() } else { sleepTimer.start(minutes: Int(minutes)) }
            pushStatus()
        case .hello, .welcome, .macStatus, .disconnect, .pong:
            break
        default:
            injector.handle(message)
        }
    }

    private func authenticate(_ session: Session, version: UInt8, deviceID: UUID, pairingID: UUID, name: String, proof: [UInt8]) {
        guard version == Message.protocolVersion else {
            log.error("Phone speaks protocol v\(version), we speak v\(Message.protocolVersion)")
            showNotice("An iPhone with a different app version tried to connect. Update the other app.")
            unauthenticated[ObjectIdentifier(session)] = nil
            session.send(.welcome(protocolVersion: Message.protocolVersion, macID: pairing.macID, name: macName))
            session.sendAndClose(.disconnect(.versionMismatch))
            return
        }

        let idsBefore = Set(pairing.credentials().map(\.pairingID))
        switch pairing.authenticate(pairingID: pairingID, deviceID: deviceID, name: name, proof: proof) {
        case .rejected:
            log.error("Rejected hello: proof did not verify")
            unauthenticated[ObjectIdentifier(session)] = nil
            session.sendAndClose(.disconnect(.unauthorized))
        case .accepted(let phone, _):
            activate(session, as: phone)
            // A re-pair from the same phone can retire its older key.
            if Set(pairing.credentials().map(\.pairingID)) != idsBefore { refreshListener() }
        }
    }

    private func activate(_ session: Session, as phone: PairedPhone) {
        session.helloTimeout?.cancel()
        unauthenticated[ObjectIdentifier(session)] = nil

        if let previous = active {
            clearActive()
            previous.sendAndClose(.disconnect(.replaced))
        }
        session.phone = phone
        active = session
        connectedPhone = phone
        notice = nil
        keepAwake.acquire(reason: "CouchRemote phone connected")
        session.send(.welcome(protocolVersion: Message.protocolVersion, macID: pairing.macID, name: macName))
        pushStatus()
        log.info("Phone connected")
    }

    private func showNotice(_ text: String) {
        notice = text
        Task {
            try? await Task.sleep(for: .seconds(60))
            if notice == text { notice = nil }
        }
    }
}
