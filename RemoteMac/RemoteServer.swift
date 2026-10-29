import AppKit
import Network
import Observation
import OSLog
import RemoteKit

/// Listens for the phone, advertises over Bonjour, and feeds decoded messages to the injector.
/// One client at a time: a new connection replaces the old one.
@Observable
final class RemoteServer {
    private(set) var isListening = false
    private(set) var isClientConnected = false
    private(set) var deviceName: String?

    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var session: Session?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private let injector = InputInjector()
    @ObservationIgnored private let keepAwake = KeepAwake()
    @ObservationIgnored private let log = Logger(subsystem: "com.adityakolte.couchremote.mac", category: "server")

    private final class Session {
        let connection: NWConnection
        var decoder = FrameDecoder()

        init(_ connection: NWConnection) { self.connection = connection }

        func send(_ message: Message) {
            connection.send(content: Data(Frame.encode(message)), completion: .contentProcessed { _ in })
        }
    }

    // MARK: Listener

    func start() {
        guard listener == nil else { return }
        do {
            let listener = try NWListener(using: Service.makeParameters())
            listener.service = NWListener.Service(
                name: Host.current().localizedName ?? "Mac",
                type: Service.type
            )
            // All Network callbacks are delivered on the main queue (`start(queue: .main)`).
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                MainActor.assumeIsolated {
                    guard let self, let listener, listener === self.listener else { return }
                    self.listenerStateChanged(state)
                }
            }
            // TODO(stage 2): pair + encrypt (e.g. PSK-TLS) before accepting; stage 1 trusts the LAN.
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.accept(connection) }
            }
            self.listener = listener
            listener.start(queue: .main)
        } catch {
            log.error("Could not create listener: \(error.localizedDescription)")
            scheduleRestart()
        }

        if wakeObserver == nil {
            // The listener can silently die across sleep; rebuild it on wake.
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.restartListener() }
            }
        }
    }

    private func restartListener() {
        listener?.cancel()
        listener = nil
        isListening = false
        start()
    }

    private func scheduleRestart() {
        Task {
            try? await Task.sleep(for: .seconds(2))
            restartListener()
        }
    }

    private func listenerStateChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            isListening = true
            log.info("Listening")
        case .failed(let error):
            log.error("Listener failed: \(error.localizedDescription)")
            isListening = false
            listener?.cancel()
            listener = nil
            scheduleRestart()
        case .cancelled:
            isListening = false
        default:
            isListening = false
        }
    }

    // MARK: Connections

    private func accept(_ connection: NWConnection) {
        if let old = session {
            // Detach first so its `.cancelled` callback is ignored as stale.
            session = nil
            old.connection.cancel()
        }
        let session = Session(connection)
        self.session = session
        deviceName = nil
        isClientConnected = false

        connection.stateUpdateHandler = { [weak self, weak session] state in
            MainActor.assumeIsolated {
                guard let self, let session, session === self.session else { return }
                switch state {
                case .ready:
                    self.isClientConnected = true
                    self.keepAwake.acquire(reason: "CouchRemote phone connected")
                    self.log.info("Client connected")
                case .failed, .cancelled:
                    self.end(session)
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
        receive(on: session)
    }

    private func end(_ session: Session) {
        guard session === self.session else { return }
        session.connection.cancel()
        self.session = nil
        isClientConnected = false
        deviceName = nil
        keepAwake.release()
        log.info("Client disconnected")
    }

    private func receive(on session: Session) {
        session.connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self, weak session] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self, let session, session === self.session else { return }
                if let data {
                    session.decoder.append([UInt8](data))
                    self.drain(session)
                    guard session === self.session else { return }
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
        while true {
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
        switch message {
        case .ping(let timestamp):
            session.send(.pong(timestamp: timestamp))
        case .hello(let name):
            deviceName = name
        default:
            injector.handle(message)
        }
    }
}
