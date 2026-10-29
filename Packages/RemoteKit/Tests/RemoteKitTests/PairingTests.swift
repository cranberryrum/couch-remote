import Foundation
import Testing
@testable import RemoteKit

@Suite struct PairingInviteTests {
    private let invite = PairingInvite(
        macID: UUID(),
        macName: "Aditya's MacBook Pro & Co — 💻",
        pairingID: UUID(),
        key: PairingInvite.randomKey()
    )

    @Test func urlRoundTrips() throws {
        let parsed = try #require(PairingInvite(url: invite.url))
        #expect(parsed == invite)
    }

    @Test func urlHasTheDocumentedShape() {
        let url = invite.url
        #expect(url.scheme == "couchremote")
        #expect(url.host == "pair")
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items["mac"] == invite.macID.uuidString)
        #expect(items["id"] == invite.pairingID.uuidString)
        #expect(Set(items.keys) == ["mac", "name", "id", "key"])
        // base64url: no padding or URL-unsafe characters
        #expect(items["key"]?.contains(where: { "+/=".contains($0) }) == false)
        #expect(Data(base64URLEncoded: items["key"] ?? "")?.count == 32)
    }

    @Test func randomKeysAre32BytesAndDistinct() {
        let a = PairingInvite.randomKey(), b = PairingInvite.randomKey()
        #expect(a.count == 32 && b.count == 32)
        #expect(a != b)
    }

    @Test(arguments: [
        "https://pair?mac=x",
        "couchremote://other?mac=01234567-89AB-CDEF-0123-456789ABCDEF",
        "couchremote://pair",
        "couchremote://pair?mac=not-a-uuid&id=01234567-89AB-CDEF-0123-456789ABCDEF&key=AAAA",
    ])
    func rejectsMalformedURLs(string: String) throws {
        let url = try #require(URL(string: string))
        #expect(PairingInvite(url: url) == nil)
    }

    @Test func rejectsShortAndLongKeys() throws {
        for length in [16, 31, 33, 64] {
            var components = URLComponents(url: invite.url, resolvingAgainstBaseURL: false)!
            components.queryItems = components.queryItems?.map {
                $0.name == "key" ? URLQueryItem(name: "key", value: Data(repeating: 7, count: length).base64URLEncodedString()) : $0
            }
            let url = try #require(components.url)
            #expect(PairingInvite(url: url) == nil)
        }
    }

    @Test func missingNameFallsBack() throws {
        var components = URLComponents(url: invite.url, resolvingAgainstBaseURL: false)!
        components.queryItems = components.queryItems?.filter { $0.name != "name" }
        let url = try #require(components.url)
        let parsed = try #require(PairingInvite(url: url))
        #expect(parsed.macName == "Mac")
    }

    @Test func base64URLRoundTripsAllLengths() throws {
        for length in 0..<40 {
            let data = Data((0..<length).map { UInt8(truncatingIfNeeded: $0 &* 37) })
            #expect(Data(base64URLEncoded: data.base64URLEncodedString()) == data)
        }
    }
}

@Suite struct HelloProofTests {
    private let key = PairingInvite.randomKey()
    private let device = UUID(), pairing = UUID()

    @Test func validProofVerifies() {
        let proof = HelloProof.make(key: key, deviceID: device, pairingID: pairing)
        #expect(proof.count == Message.proofLength)
        #expect(HelloProof.verify(proof, key: key, deviceID: device, pairingID: pairing))
    }

    @Test func proofIsBoundToKeyDeviceAndPairing() {
        let proof = HelloProof.make(key: key, deviceID: device, pairingID: pairing)
        #expect(!HelloProof.verify(proof, key: PairingInvite.randomKey(), deviceID: device, pairingID: pairing))
        #expect(!HelloProof.verify(proof, key: key, deviceID: UUID(), pairingID: pairing))
        #expect(!HelloProof.verify(proof, key: key, deviceID: device, pairingID: UUID()))
        #expect(!HelloProof.verify([UInt8](repeating: 0, count: 32), key: key, deviceID: device, pairingID: pairing))
        #expect(!HelloProof.verify([], key: key, deviceID: device, pairingID: pairing))
    }
}

@Suite struct PairingLedgerTests {
    private let macID = UUID()
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func hello(_ invite: PairingInvite, device: UUID, key: Data? = nil) -> (UUID, UUID, [UInt8]) {
        (invite.pairingID, device, HelloProof.make(key: key ?? invite.key, deviceID: device, pairingID: invite.pairingID))
    }

    @Test func pendingInviteExpiresAfterFiveMinutes() {
        var ledger = PairingLedger()
        let invite = ledger.beginPairing(macID: macID, macName: "M", now: start)
        #expect(ledger.credentials(now: start).count == 1)
        #expect(ledger.credentials(now: start.addingTimeInterval(299)).count == 1)
        #expect(ledger.credentials(now: start.addingTimeInterval(300)).isEmpty)

        let early = ledger.expirePending(now: start.addingTimeInterval(299))
        #expect(!early)
        let onTime = ledger.expirePending(now: start.addingTimeInterval(300))
        #expect(onTime)
        #expect(ledger.pending == nil)

        let device = UUID()
        let (pid, did, proof) = hello(invite, device: device)
        let outcome = ledger.authenticate(pairingID: pid, deviceID: did, name: "P", proof: proof, now: start.addingTimeInterval(301))
        #expect(outcome == .rejected)
    }

    @Test func expiredPendingIsRejectedEvenBeforeItIsPurged() {
        var ledger = PairingLedger()
        let invite = ledger.beginPairing(macID: macID, macName: "M", now: start)
        let (pid, did, proof) = hello(invite, device: UUID())
        let late = start.addingTimeInterval(PairingLedger.pendingLifetime + 1)
        let outcome = ledger.authenticate(pairingID: pid, deviceID: did, name: "P", proof: proof, now: late)
        #expect(outcome == .rejected)
        #expect(ledger.phones.isEmpty)
    }

    @Test func validHelloPromotesPendingToPaired() {
        var ledger = PairingLedger()
        let invite = ledger.beginPairing(macID: macID, macName: "M", now: start)
        let device = UUID()
        let (pid, did, proof) = hello(invite, device: device)
        guard case .accepted(let phone, let isNew) = ledger.authenticate(pairingID: pid, deviceID: did, name: "Aditya's iPhone", proof: proof, now: start.addingTimeInterval(10)) else {
            Issue.record("expected acceptance")
            return
        }
        #expect(isNew)
        #expect(phone.name == "Aditya's iPhone" && phone.deviceID == device && phone.key == invite.key)
        #expect(ledger.pending == nil)
        #expect(ledger.phones == [phone])
        // The key stays valid after the invite is gone.
        #expect(ledger.credentials(now: start.addingTimeInterval(10_000)) == [phone.credential])
    }

    @Test func wrongProofDoesNotPromote() {
        var ledger = PairingLedger()
        let invite = ledger.beginPairing(macID: macID, macName: "M", now: start)
        let (pid, did, proof) = hello(invite, device: UUID(), key: PairingInvite.randomKey())
        let outcome = ledger.authenticate(pairingID: pid, deviceID: did, name: "X", proof: proof, now: start)
        #expect(outcome == .rejected)
        #expect(ledger.phones.isEmpty)
        #expect(ledger.pending != nil)
    }

    @Test func unknownPairingIDIsRejected() {
        var ledger = PairingLedger()
        _ = ledger.beginPairing(macID: macID, macName: "M", now: start)
        let key = PairingInvite.randomKey(), id = UUID(), device = UUID()
        let proof = HelloProof.make(key: key, deviceID: device, pairingID: id)
        let outcome = ledger.authenticate(pairingID: id, deviceID: device, name: "X", proof: proof, now: start)
        #expect(outcome == .rejected)
    }

    @Test func pairedPhoneReconnectsWithoutPromotionAndRefreshesItsName() {
        var ledger = PairingLedger()
        let invite = ledger.beginPairing(macID: macID, macName: "M", now: start)
        let device = UUID()
        var (pid, did, proof) = hello(invite, device: device)
        _ = ledger.authenticate(pairingID: pid, deviceID: did, name: "Old name", proof: proof, now: start)

        (pid, did, proof) = hello(invite, device: device)
        guard case .accepted(let phone, let isNew) = ledger.authenticate(pairingID: pid, deviceID: did, name: "New name", proof: proof, now: start.addingTimeInterval(86_400)) else {
            Issue.record("expected acceptance")
            return
        }
        #expect(!isNew)
        #expect(phone.name == "New name")
        #expect(ledger.phones.count == 1)
    }

    @Test func pairedPhoneWithBadProofIsRejected() {
        var ledger = PairingLedger()
        let invite = ledger.beginPairing(macID: macID, macName: "M", now: start)
        let device = UUID()
        let (pid, did, proof) = hello(invite, device: device)
        _ = ledger.authenticate(pairingID: pid, deviceID: did, name: "P", proof: proof, now: start)
        let bad = hello(invite, device: device, key: PairingInvite.randomKey())
        let outcome = ledger.authenticate(pairingID: bad.0, deviceID: bad.1, name: "P", proof: bad.2, now: start)
        #expect(outcome == .rejected)
    }

    @Test func rePairingTheSamePhoneReplacesItsOldRecord() {
        var ledger = PairingLedger()
        let device = UUID()
        for _ in 0..<2 {
            let invite = ledger.beginPairing(macID: macID, macName: "M", now: start)
            let (pid, did, proof) = hello(invite, device: device)
            _ = ledger.authenticate(pairingID: pid, deviceID: did, name: "P", proof: proof, now: start)
        }
        #expect(ledger.phones.count == 1)
    }

    @Test func differentPhonesCoexistAndForgetRemovesOnlyOne() {
        var ledger = PairingLedger()
        var ids: [UUID] = []
        for _ in 0..<2 {
            let invite = ledger.beginPairing(macID: macID, macName: "M", now: start)
            let (pid, did, proof) = hello(invite, device: UUID())
            _ = ledger.authenticate(pairingID: pid, deviceID: did, name: "P", proof: proof, now: start)
            ids.append(pid)
        }
        #expect(ledger.phones.count == 2)
        let removed = ledger.forget(pairingID: ids[0])
        #expect(removed)
        #expect(ledger.phones.map(\.pairingID) == [ids[1]])
        let removedAgain = ledger.forget(pairingID: ids[0])
        #expect(!removedAgain)
        #expect(ledger.credentials(now: start).count == 1)
    }

    @Test func beginPairingReplacesAnEarlierInvite() {
        var ledger = PairingLedger()
        let first = ledger.beginPairing(macID: macID, macName: "M", now: start)
        let second = ledger.beginPairing(macID: macID, macName: "M", now: start)
        let (pid, did, proof) = hello(first, device: UUID())
        let outcome = ledger.authenticate(pairingID: pid, deviceID: did, name: "P", proof: proof, now: start)
        #expect(outcome == .rejected)
        #expect(ledger.pending?.invite == second)
    }

    @Test func ledgerPersistsAsJSON() throws {
        var ledger = PairingLedger()
        let invite = ledger.beginPairing(macID: macID, macName: "M", now: start)
        let (pid, did, proof) = hello(invite, device: UUID())
        _ = ledger.authenticate(pairingID: pid, deviceID: did, name: "P", proof: proof, now: start)
        let data = try JSONEncoder().encode(ledger.phones)
        #expect(try JSONDecoder().decode([PairedPhone].self, from: data) == ledger.phones)
    }
}

@Suite struct SecretStoreTests {
    @Test func inMemoryStoreBehavesLikeAKeyValueStore() throws {
        let store = InMemorySecretStore()
        #expect(store.read("a") == nil)
        try store.write(Data([1]), account: "a")
        try store.write(Data([2]), account: "a")
        #expect(store.read("a") == Data([2]))
        store.delete("a")
        #expect(store.read("a") == nil)
    }

    @Test func pairedMacPrefersCustomName() {
        var mac = PairedMac(macID: UUID(), macName: "Work", pairingID: UUID(), key: Data(repeating: 1, count: 32))
        #expect(mac.displayName == "Work")
        mac.customName = "Desk"
        #expect(mac.displayName == "Desk")
    }
}
