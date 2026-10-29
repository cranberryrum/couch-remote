import Foundation
import Observation
import OSLog
import RemoteKit

/// The Mac's identity and trusted phones, persisted in the Keychain. The rules live in
/// `PairingLedger` (unit-tested in RemoteKit); this adds storage and observation.
@Observable
final class PairingStore {
    /// Stable random ID, generated on first launch. Never derived from the hostname.
    let macID: UUID

    private(set) var phones: [PairedPhone]
    private(set) var pending: PendingPairing?
    /// Set when a pending invite was just consumed; the pairing window shows it.
    private(set) var lastPairedPhoneName: String?

    @ObservationIgnored private var ledger: PairingLedger
    @ObservationIgnored private let secrets: SecretStore
    @ObservationIgnored private let log = Logger(subsystem: "com.adityakolte.couchremote.mac", category: "pairing")

    private static let macIDAccount = "macID"
    private static let phonesAccount = "pairedPhones"

    init(secrets: SecretStore = KeychainSecretStore(service: "com.adityakolte.couchremote.mac")) {
        self.secrets = secrets
        let log = Logger(subsystem: "com.adityakolte.couchremote.mac", category: "pairing")

        if let data = secrets.read(Self.macIDAccount),
           let string = String(data: data, encoding: .utf8),
           let id = UUID(uuidString: string) {
            macID = id
        } else {
            let id = UUID()
            do { try secrets.write(Data(id.uuidString.utf8), account: Self.macIDAccount) }
            catch { log.error("Could not store macID in the Keychain: \(String(describing: error))") }
            macID = id
        }

        let stored = secrets.read(Self.phonesAccount)
            .flatMap { try? JSONDecoder().decode([PairedPhone].self, from: $0) } ?? []
        ledger = PairingLedger(phones: stored)
        phones = stored
    }

    func credentials() -> [PairingCredential] { ledger.credentials() }

    func beginPairing(macName: String) -> PairingInvite {
        let invite = ledger.beginPairing(macID: macID, macName: macName)
        lastPairedPhoneName = nil
        sync()
        return invite
    }

    func cancelPending() {
        ledger.cancelPending()
        sync()
    }

    /// True if an invite just expired (the listener's key list is now stale).
    @discardableResult
    func expirePending() -> Bool {
        guard ledger.expirePending() else { return false }
        sync()
        return true
    }

    func authenticate(pairingID: UUID, deviceID: UUID, name: String, proof: [UInt8]) -> PairingLedger.Outcome {
        let outcome = ledger.authenticate(pairingID: pairingID, deviceID: deviceID, name: name, proof: proof)
        if case .accepted(let phone, let isNewPairing) = outcome {
            if isNewPairing { lastPairedPhoneName = phone.name }
            persist()
            sync()
        }
        return outcome
    }

    @discardableResult
    func forget(pairingID: UUID) -> Bool {
        guard ledger.forget(pairingID: pairingID) else { return false }
        persist()
        sync()
        return true
    }

    private func sync() {
        phones = ledger.phones
        pending = ledger.pending
    }

    private func persist() {
        do {
            try secrets.write(try JSONEncoder().encode(ledger.phones), account: Self.phonesAccount)
        } catch {
            log.error("Could not store paired phones in the Keychain: \(String(describing: error))")
        }
    }
}
