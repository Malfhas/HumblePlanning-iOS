import Foundation
import Security
import Synchronization

/// Small secrets: the session, the key of the offline files.
public protocol SecretStore: Sendable {
    func read(_ key: String) -> Data?
    func write(_ key: String, _ value: Data?)
}

/// The Keychain of this device only: never in a backup, never moved to another phone, readable after
/// the first unlock (background refresh needs it).
public final class KeychainStore: SecretStore {
    private let service: String
    private let accessGroup: String?

    public init(service: String = "com.humbleplanning.app", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    private func query(_ key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    public func read(_ key: String) -> Data? {
        var query = query(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    public func write(_ key: String, _ value: Data?) {
        let query = query(key)
        guard let value else {
            SecItemDelete(query as CFDictionary)
            return
        }
        let attributes: [String: Any] = [
            kSecValueData as String: value,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        }
    }
}

/// For the tests and the previews.
public final class MemorySecretStore: SecretStore {
    private let values = Mutex<[String: Data]>([:])

    public init() {}

    public func read(_ key: String) -> Data? { values.withLock { $0[key] } }
    public func write(_ key: String, _ value: Data?) { values.withLock { $0[key] = value } }
}

/// The session of the signed-in account, in the secret store.
public struct SessionStore: Sendable {
    private let secrets: any SecretStore

    public init(secrets: any SecretStore) {
        self.secrets = secrets
    }

    public func load() -> ServerSession? {
        secrets.read("session").flatMap { try? JSONDecoder().decode(ServerSession.self, from: $0) }
    }

    public func save(_ session: ServerSession?) {
        secrets.write("session", session.flatMap { try? JSONEncoder().encode($0) })
    }
}
