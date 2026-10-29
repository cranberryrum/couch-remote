import Network
import Observation
import OSLog
import RemoteKit
import UIKit

struct DiscoveredMac: Identifiable, Equatable {
    let name: String
    let endpoint: NWEndpoint
    var id: String { name }
}

/// Finds the Mac over Bonjour, keeps a connection to it, and measures round-trip time.
@Observable
final class RemoteClient {
    enum State: Equatable {
        case idle
        case searching
        case choosing
        case connecting(String)
        case connected(String)
        case localNetworkDenied
    }

    private(set) var state: State = .idle
    private(set) var rttMs: Double?
    private(set) var discovered: [DiscoveredMac] = []

    var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var connection: NWConnection?
    @ObservationIgnored private var decoder = FrameDecoder()
    @ObservationIgnored private var pingTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var lastPong: UInt64 = 0
    @ObservationIgnored private let log = Logger(subsystem: "com.adityakolte.couchremote.ios", category: "client")

    private static let lastMacKey = "lastMacName"
    /// kDNSServiceErr_PolicyDenied: what Network reports when Local Network access is refused.
    private static let policyDenied: Int32 = -65570
    private static let pongTimeout: UInt64 = 4_000_000_000

    private static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

    // MARK: Lifecycle

    /// Idempotent. Call when the app becomes active.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        state = .searching

        let browser = NWBrowser(for: .bonjour(type: Service.type, domain: nil), using: Service.makeParameters())
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

    /// Call when the app goes to the background so the Mac releases its keep-awake hold promptly.
    func stop() {
        isRunning = false
        retryTask?.cancel()
        retryTask = nil
        browser?.cancel()
        browser = nil
        dropConnection()
        discovered = []
        state = .idle
    }

    /// Picker choice (or the automatic choice).
    func connect(_ mac: DiscoveredMac) {
        guard isRunning else { return }
        dropConnection()
        UserDefaults.standard.set(mac.name, forKey: Self.lastMacKey)
        state = .connecting(mac.name)

        let connection = NWConnection(to: mac.endpoint, using: Service.makeParameters())
        self.connection = connection
        let macName = mac.name
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            MainActor.assumeIsolated {
                guard let self, let connection, connection === self.connection else { return }
                self.connectionStateChanged(state, macName: macName)
            }
        }
        connection.start(queue: .main)
    }

    func send(_ message: Message) {
        guard isConnected, let connection else { return }
        connection.send(content: Data(Frame.encode(message)), completion: .contentProcessed { _ in })
    }

    // MARK: Discovery

    private func browserStateChanged(_ state: NWBrowser.State) {
        switch state {
        case .waiting(let error), .failed(let error):
            if case .dns(let code) = error, code == Self.policyDenied {
                self.state = .localNetworkDenied
            } else {
                log.error("Browser: \(error.localizedDescription)")
            }
        default:
            break
        }
    }

    private func browseResultsChanged(_ results: Set<NWBrowser.Result>) {
        // The same Mac can appear once per interface (Wi-Fi, peer-to-peer); keep one,
        // preferring Wi-Fi/Ethernet.
        var best: [String: (mac: DiscoveredMac, rank: Int)] = [:]
        for result in results {
            guard case let .service(name, _, _, _) = result.endpoint else { continue }
            let rank = result.interfaces.contains { $0.type == .wifi || $0.type == .wiredEthernet } ? 0 : 1
            if let existing = best[name], existing.rank <= rank { continue }
            best[name] = (DiscoveredMac(name: name, endpoint: result.endpoint), rank)
        }
        discovered = best.values.map(\.mac).sorted { $0.name < $1.name }
        if connection == nil { chooseAndConnect() }
    }

    private func chooseAndConnect() {
        guard isRunning, connection == nil, state != .localNetworkDenied else { return }
        let last = UserDefaults.standard.string(forKey: Self.lastMacKey)
        if let mac = discovered.first(where: { $0.name == last }) ?? (discovered.count == 1 ? discovered.first : nil) {
            connect(mac)
        } else {
            state = discovered.isEmpty ? .searching : .choosing
        }
    }

    // MARK: Connection

    private func connectionStateChanged(_ state: NWConnection.State, macName: String) {
        switch state {
        case .ready:
            self.state = .connected(macName)
            decoder = FrameDecoder()
            send(.hello(name: UIDevice.current.name))
            receive()
            startPinging()
        case .waiting, .failed, .cancelled:
            handleDisconnect()
        default:
            break
        }
    }

    private func receive() {
        guard let connection else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 2048) { [weak self, weak connection] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self, let connection, connection === self.connection else { return }
                if let data {
                    self.decoder.append([UInt8](data))
                    self.drain()
                    guard connection === self.connection else { return }
                }
                if error != nil || isComplete {
                    self.handleDisconnect()
                    return
                }
                self.receive()
            }
        }
    }

    private func drain() {
        while true {
            do {
                guard let message = try decoder.next() else { return }
                if case .pong(let timestamp) = message {
                    let now = Self.now()
                    lastPong = now
                    rttMs = Double(now &- timestamp) / 1_000_000
                }
            } catch {
                log.error("Protocol error: \(String(describing: error))")
                handleDisconnect()
                return
            }
        }
    }

    private func startPinging() {
        pingTask?.cancel()
        lastPong = Self.now()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if Self.now() - lastPong > Self.pongTimeout {
                    handleDisconnect()
                    return
                }
                send(.ping(timestamp: Self.now()))
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func dropConnection() {
        pingTask?.cancel()
        pingTask = nil
        let old = connection
        connection = nil // detach first so the cancel callback is ignored
        old?.cancel()
        rttMs = nil
    }

    /// Drops the link and retries quickly; the browser keeps running so the Mac is still known.
    private func handleDisconnect() {
        guard isRunning else { return }
        dropConnection()
        if state != .localNetworkDenied { state = .searching }
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.chooseAndConnect()
        }
    }
}
