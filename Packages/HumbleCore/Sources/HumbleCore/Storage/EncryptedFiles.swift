import CryptoKit
import Foundation

/// Planning data kept on the phone (references, the offline copy, scheduled reminders): encrypted with
/// AES-GCM (`nonce ‖ ciphertext ‖ tag`, like the Android app) with a key of the Keychain of this device,
/// excluded from backups. A file that cannot be decrypted reads as absent.
public struct EncryptedFiles: Sendable {
    public enum Name: String, Sendable {
        case references = "references.bin"
        case tasks = "tasks.bin"
        case reminders = "reminders.bin"
    }

    private let directory: URL
    private let secrets: any SecretStore

    public init(directory: URL, secrets: any SecretStore) {
        self.directory = directory
        self.secrets = secrets
    }

    /// `Application Support/offline`.
    public static func standard(secrets: any SecretStore) -> EncryptedFiles {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return EncryptedFiles(directory: support.appending(path: "offline", directoryHint: .isDirectory), secrets: secrets)
    }

    private func key() -> SymmetricKey {
        if let data = secrets.read("data-key"), data.count == 32 { return SymmetricKey(data: data) }
        let key = SymmetricKey(size: .bits256)
        secrets.write("data-key", key.withUnsafeBytes { Data($0) })
        return key
    }

    public func read<T: Decodable>(_ type: T.Type, _ name: Name) -> T? {
        guard let sealed = try? Data(contentsOf: directory.appending(path: name.rawValue)),
              let box = try? AES.GCM.SealedBox(combined: sealed),
              let plain = try? AES.GCM.open(box, using: key()) else { return nil }
        return try? JSONDecoder().decode(T.self, from: plain)
    }

    public func write(_ value: some Encodable, _ name: Name) throws {
        let plain = try JSONEncoder().encode(value)
        guard let sealed = try AES.GCM.seal(plain, using: key()).combined else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        let file = directory.appending(path: name.rawValue)
        #if os(iOS)
        try sealed.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try sealed.write(to: file, options: .atomic)
        #endif
    }

    public func delete(_ name: Name) {
        try? FileManager.default.removeItem(at: directory.appending(path: name.rawValue))
    }

    public func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
