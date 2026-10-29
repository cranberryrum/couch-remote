import Foundation
import Network
import Security

/// A pairing's shared secret. `pairingID` is the TLS-PSK *identity* (sent in the clear
/// during the handshake, so it must carry no secret); `key` is the 32-byte PSK.
public struct PairingCredential: Sendable, Equatable {
    public var pairingID: UUID
    public var key: Data

    public init(pairingID: UUID, key: Data) {
        self.pairingID = pairingID
        self.key = key
    }
}

/// TLS 1.2 with a pre-shared key (TLS_PSK_WITH_AES_128_GCM_SHA256). There is deliberately
/// no plaintext variant: a peer without a valid key fails the handshake.
public enum SecureTransport {
    /// Listener parameters accepting any of `credentials`. The TLS stack matches the
    /// client's PSK identity against these; an unknown identity or wrong key fails.
    public static func serverParameters(credentials: [PairingCredential]) -> NWParameters {
        makeParameters(credentials: credentials)
    }

    public static func clientParameters(credential: PairingCredential) -> NWParameters {
        makeParameters(credentials: [credential])
    }

    private static func makeParameters(credentials: [PairingCredential]) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions

        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv12)
        // Every connection must prove the key in a full handshake. Without this, a cached session
        // can be resumed without re-checking the PSK (so a forgotten phone, or a wrong key sent
        // by a process that already holds a session, would still get through TLS), and a client
        // could report "ready" before the server has verified it.
        sec_protocol_options_set_tls_resumption_enabled(options, false)
        sec_protocol_options_set_tls_tickets_enabled(options, false)
        sec_protocol_options_set_tls_false_start_enabled(options, false)
        sec_protocol_options_append_tls_ciphersuite(
            options,
            tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!
        )
        for credential in credentials {
            sec_protocol_options_add_pre_shared_key(
                options,
                dispatchData(credential.key),
                dispatchData(Data(credential.pairingID.uuidString.utf8))
            )
        }

        let parameters = NWParameters(tls: tls, tcp: Service.makeTCPOptions())
        parameters.includePeerToPeer = true
        return parameters
    }

    private static func dispatchData(_ data: Data) -> __DispatchData {
        data.withUnsafeBytes { DispatchData(bytes: $0) } as __DispatchData
    }
}
