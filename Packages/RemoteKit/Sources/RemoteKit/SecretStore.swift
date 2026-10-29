import Foundation
import Security

/// Where pairing secrets live. Production uses the Keychain; tests use memory.
public protocol SecretStore: Sendable {
    func read(_ account: String) -> Data?
    func write(_ data: Data, account: String) throws
    func delete(_ account: String)
}

public struct KeychainError: Error, Equatable {
    public let status: OSStatus
}

/// Generic-password items scoped by `service`. On macOS this is the login keychain (no
/// entitlement needed for a non-sandboxed app); on iOS the app's own keychain, readable
/// only after first unlock and never synced or backed up.
public struct KeychainSecretStore: SecretStore {
    public let service: String

    public init(service: String) {
        self.service = service
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func read(_ account: String) -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    public func write(_ data: Data, account: String) throws {
        let update = [kSecValueData as String: data]
        var status = SecItemUpdate(baseQuery(account) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery(account)
            add[kSecValueData as String] = data
            #if os(iOS)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            #endif
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func delete(_ account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }
}

public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]

    public init() {}

    public func read(_ account: String) -> Data? {
        lock.withLock { items[account] }
    }

    public func write(_ data: Data, account: String) throws {
        lock.withLock { items[account] = data }
    }

    public func delete(_ account: String) {
        lock.withLock { items[account] = nil }
    }
}
