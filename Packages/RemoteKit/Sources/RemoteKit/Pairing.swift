import CryptoKit
import Foundation
import Security

// MARK: Invite (QR / URL)

/// What the Mac's QR code carries:
/// `couchremote://pair?mac=<macID>&name=<macName>&id=<pairingID>&key=<base64url 32 bytes>`
public struct PairingInvite: Equatable, Sendable {
    public static let scheme = "couchremote"
    public static let keyLength = 32

    public var macID: UUID
    public var macName: String
    public var pairingID: UUID
    public var key: Data

    public init(macID: UUID, macName: String, pairingID: UUID, key: Data) {
        self.macID = macID
        self.macName = macName
        self.pairingID = pairingID
        self.key = key
    }

    public var credential: PairingCredential {
        PairingCredential(pairingID: pairingID, key: key)
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "pair"
        components.queryItems = [
            URLQueryItem(name: "mac", value: macID.uuidString),
            URLQueryItem(name: "name", value: macName),
            URLQueryItem(name: "id", value: pairingID.uuidString),
            URLQueryItem(name: "key", value: key.base64URLEncodedString()),
        ]
        return components.url!
    }

    /// Fails unless every field is present and well-formed (the key must be exactly 32 bytes).
    public init?(url: URL) {
        guard url.scheme == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host == "pair"
        else { return nil }

        func value(_ name: String) -> String? {
            components.queryItems?.first { $0.name == name }?.value
        }
        guard let macString = value("mac"), let macID = UUID(uuidString: macString),
              let idString = value("id"), let pairingID = UUID(uuidString: idString),
              let keyString = value("key"), let key = Data(base64URLEncoded: keyString),
              key.count == Self.keyLength
        else { return nil }

        let name = (value("name") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(macID: macID, macName: name.isEmpty ? "Mac" : name, pairingID: pairingID, key: key)
    }

    /// 32 bytes from the system CSPRNG.
    public static func randomKey() -> Data {
        var bytes = [UInt8](repeating: 0, count: keyLength)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return Data(bytes)
    }
}

extension Data {
    public func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}

// MARK: Hello proof

/// The TLS stack doesn't tell the server which PSK identity a client used, so the phone
/// proves it in `hello`: an HMAC under the pairing key over (deviceID, pairingID). The
/// handshake already proved the peer holds *a* valid key; this ties the claimed pairing to it.
public enum HelloProof {
    private static let label = Array("couchremote.hello.v2".utf8)

    private static func message(deviceID: UUID, pairingID: UUID) -> Data {
        Data(label + deviceID.wireBytesForProof + pairingID.wireBytesForProof)
    }

    public static func make(key: Data, deviceID: UUID, pairingID: UUID) -> [UInt8] {
        let mac = HMAC<SHA256>.authenticationCode(
            for: message(deviceID: deviceID, pairingID: pairingID),
            using: SymmetricKey(data: key)
        )
        return Array(mac)
    }

    public static func verify(_ proof: [UInt8], key: Data, deviceID: UUID, pairingID: UUID) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(
            proof,
            authenticating: message(deviceID: deviceID, pairingID: pairingID),
            using: SymmetricKey(data: key)
        )
    }
}

private extension UUID {
    var wireBytesForProof: [UInt8] { withUnsafeBytes(of: uuid) { Array($0) } }
}

// MARK: Paired device records

/// A phone the Mac trusts. Stored in the Mac's Keychain.
public struct PairedPhone: Codable, Equatable, Sendable, Identifiable {
    public var pairingID: UUID
    public var key: Data
    public var deviceID: UUID?
    public var name: String
    public var pairedAt: Date

    public var id: UUID { pairingID }

    public init(pairingID: UUID, key: Data, deviceID: UUID?, name: String, pairedAt: Date) {
        self.pairingID = pairingID
        self.key = key
        self.deviceID = deviceID
        self.name = name
        self.pairedAt = pairedAt
    }

    public var credential: PairingCredential { PairingCredential(pairingID: pairingID, key: key) }
}

/// A Mac the phone has paired with. Stored in the phone's Keychain.
public struct PairedMac: Codable, Equatable, Sendable, Identifiable {
    public var macID: UUID
    /// The Mac's own name, refreshed from `welcome` on every connection.
    public var macName: String
    /// A name the user chose on the phone; wins over `macName` when set.
    public var customName: String?
    public var pairingID: UUID
    public var key: Data

    public var id: UUID { macID }
    public var displayName: String { customName ?? macName }
    public var credential: PairingCredential { PairingCredential(pairingID: pairingID, key: key) }

    public init(macID: UUID, macName: String, customName: String? = nil, pairingID: UUID, key: Data) {
        self.macID = macID
        self.macName = macName
        self.customName = customName
        self.pairingID = pairingID
        self.key = key
    }

    public init(invite: PairingInvite) {
        self.init(macID: invite.macID, macName: invite.macName, pairingID: invite.pairingID, key: invite.key)
    }
}

// MARK: Ledger (Mac side logic, no I/O)

public struct PendingPairing: Equatable, Sendable {
    public var invite: PairingInvite
    public var expiresAt: Date
}

/// The Mac's pairing rules, free of UI and storage so they can be unit-tested:
/// one pending invite at a time that expires, promotion to a paired phone on the first
/// valid `hello`, and one record per physical phone.
public struct PairingLedger: Sendable {
    public static let pendingLifetime: TimeInterval = 5 * 60

    public enum Outcome: Equatable, Sendable {
        case rejected
        case accepted(PairedPhone, isNewPairing: Bool)
    }

    public private(set) var phones: [PairedPhone]
    public private(set) var pending: PendingPairing?

    public init(phones: [PairedPhone] = []) {
        self.phones = phones
    }

    /// Replaces any earlier pending invite.
    public mutating func beginPairing(
        macID: UUID,
        macName: String,
        now: Date = Date(),
        pairingID: UUID = UUID(),
        key: Data = PairingInvite.randomKey()
    ) -> PairingInvite {
        let invite = PairingInvite(macID: macID, macName: macName, pairingID: pairingID, key: key)
        pending = PendingPairing(invite: invite, expiresAt: now.addingTimeInterval(Self.pendingLifetime))
        return invite
    }

    public mutating func cancelPending() { pending = nil }

    /// Drops an expired invite. Returns true if one was dropped.
    @discardableResult
    public mutating func expirePending(now: Date = Date()) -> Bool {
        guard let pending, pending.expiresAt <= now else { return false }
        self.pending = nil
        return true
    }

    /// Keys the TLS listener should accept right now: every paired phone plus an unexpired invite.
    public func credentials(now: Date = Date()) -> [PairingCredential] {
        var result = phones.map(\.credential)
        if let pending, pending.expiresAt > now { result.append(pending.invite.credential) }
        return result
    }

    /// Verifies a `hello`. A valid proof under a pending invite promotes it to a paired phone;
    /// a re-pair from the same physical phone (same `deviceID`) replaces its older record.
    public mutating func authenticate(
        pairingID: UUID,
        deviceID: UUID,
        name: String,
        proof: [UInt8],
        now: Date = Date()
    ) -> Outcome {
        if let index = phones.firstIndex(where: { $0.pairingID == pairingID }) {
            guard HelloProof.verify(proof, key: phones[index].key, deviceID: deviceID, pairingID: pairingID) else {
                return .rejected
            }
            phones[index].deviceID = deviceID
            if !name.isEmpty { phones[index].name = name }
            return .accepted(phones[index], isNewPairing: false)
        }

        guard let pending, pending.invite.pairingID == pairingID, pending.expiresAt > now,
              HelloProof.verify(proof, key: pending.invite.key, deviceID: deviceID, pairingID: pairingID)
        else { return .rejected }

        phones.removeAll { $0.deviceID == deviceID }
        let phone = PairedPhone(
            pairingID: pairingID,
            key: pending.invite.key,
            deviceID: deviceID,
            name: name.isEmpty ? "iPhone" : name,
            pairedAt: now
        )
        phones.append(phone)
        self.pending = nil
        return .accepted(phone, isNewPairing: true)
    }

    @discardableResult
    public mutating func forget(pairingID: UUID) -> Bool {
        let before = phones.count
        phones.removeAll { $0.pairingID == pairingID }
        return phones.count != before
    }
}
