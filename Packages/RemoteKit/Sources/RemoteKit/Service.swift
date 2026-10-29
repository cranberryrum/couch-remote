import Network

/// Bonjour constants shared by the Mac listener and the iPhone client.
public enum Service {
    public static let type = "_couchremote._tcp"

    /// TXT-record key carrying the Mac's stable ID, so a phone can match a discovered
    /// service to a paired Mac without trusting the (changeable, non-unique) name.
    public static let txtMacID = "mid"
    /// TXT-record key carrying the protocol version.
    public static let txtVersion = "v"

    /// TCP settings for the control channel: Nagle off so small motion packets leave
    /// immediately, keepalive so a vanished phone is noticed within ~11 s.
    static func makeTCPOptions() -> NWProtocolTCP.Options {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 5
        tcp.keepaliveInterval = 2
        tcp.keepaliveCount = 3
        return tcp
    }

    /// Parameters for browsing only (no connection is ever made with these).
    public static func makeBrowseParameters() -> NWParameters {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        return parameters
    }
}
