import Network

/// Bonjour + transport settings shared by the Mac listener and the iPhone client.
public enum Service {
    public static let type = "_couchremote._tcp"

    /// A fresh `NWParameters` for the control channel: TCP with Nagle off so small
    /// motion packets leave immediately, keepalive so a vanished phone is noticed
    /// within ~11 s, and peer-to-peer allowed.
    public static func makeParameters() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 5
        tcp.keepaliveInterval = 2
        tcp.keepaliveCount = 3
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }
}
