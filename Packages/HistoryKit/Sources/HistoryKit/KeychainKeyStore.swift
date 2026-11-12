import Foundation

#if canImport(Security)
import CryptoKit
import Security
#endif

/// Errors from a keychain-backed key store.
public enum KeychainError: Error, Hashable, Sendable {
    /// The Security framework returned a status this code does not handle.
    case unexpectedStatus(OSStatus)
    /// The stored value exists but is not the expected kind or shape.
    case dataCorrupted
    /// A device key must be exactly this many bytes.
    case invalidKeyLength(expected: Int, found: Int)
    /// The system random number generator failed.
    case randomGenerationFailed(OSStatus)
}

extension KeychainError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .unexpectedStatus(status):
            #if canImport(Security)
            let message = SecCopyErrorMessageString(status, nil) as String?
                ?? "OSStatus \(status)"
            return "Keychain error: \(message)"
            #else
            return "Keychain error: OSStatus \(status)"
            #endif
        case .dataCorrupted:
            return "Keychain data is unreadable."
        case let .invalidKeyLength(expected, found):
            return "Device key must be \(expected) bytes, got \(found)."
        case let .randomGenerationFailed(status):
            return "Could not generate a random device key (OSStatus \(status))."
        }
    }
}

/// Storage for the app's random device key and an optional remembered password.
///
/// Implementations must be safe to call from any thread. The remembered password
/// is encrypted with the device key before it is stored; no plaintext password is
/// written to the keychain, to history files or to manifests.
public protocol KeychainKeyStore: Sendable {
    /// Returns the stored 32-byte device key, creating and storing one on first use.
    func deviceKey() throws -> Data
    /// Replaces the device key. Used when migrating or resetting a device identity.
    ///
    /// A password remembered under the old key cannot be decrypted afterwards;
    /// clear it first if that matters.
    func setDeviceKey(_ key: Data) throws
    /// The remembered password, or `nil` when the user did not ask to remember it.
    func rememberedPassword() throws -> String?
    /// Stores the remembered password, or removes it when `password` is `nil`.
    func setRememberedPassword(_ password: String?) throws
}

#if canImport(Security)
/// The real store: generic-password items in the user's keychain.
///
/// Items are created with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, so
/// they survive a restart after the first unlock but never move to another device
/// through a backup.
public final class SecurityKeychainKeyStore: KeychainKeyStore, @unchecked Sendable {
    /// Default service name used to namespace the two items.
    public static let defaultService = "com.noteapp.historykit"

    private static let deviceKeyAccount = "device-key"
    private static let rememberedPasswordAccount = "remembered-password"
    private static let deviceKeyByteCount = 32
    private static let rememberedPasswordVersion: UInt8 = 1

    /// Serialises first-use key creation and read-modify-write of the two items.
    private let lock = NSLock()

    /// Keychain service name.
    public let service: String
    /// Optional keychain access group for a signed app group.
    public let accessGroup: String?
    /// Whether queries target the modern data-protection keychain.
    public let usesDataProtectionKeychain: Bool

    /// Creates a store for `service`, optionally restricted to an app-group `accessGroup`.
    ///
    /// `usesDataProtectionKeychain` defaults to true. An unsigned Mac build may
    /// need to pass false because the data-protection keychain requires a signing
    /// entitlement there.
    public init(
        service: String = SecurityKeychainKeyStore.defaultService,
        accessGroup: String? = nil,
        usesDataProtectionKeychain: Bool = true
    ) {
        self.service = service
        self.accessGroup = accessGroup
        self.usesDataProtectionKeychain = usesDataProtectionKeychain
    }

    public func deviceKey() throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        return try deviceKeyLocked()
    }

    public func setDeviceKey(_ key: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        try setDeviceKeyLocked(key)
    }

    public func rememberedPassword() throws -> String? {
        lock.lock()
        defer { lock.unlock() }

        guard let data = try read(account: Self.rememberedPasswordAccount) else {
            return nil
        }
        guard data.count > 1,
              data[data.startIndex] == Self.rememberedPasswordVersion else {
            throw KeychainError.dataCorrupted
        }

        do {
            let box = try AES.GCM.SealedBox(combined: Data(data.dropFirst()))
            guard let storedKey = try storedDeviceKey() else {
                throw KeychainError.dataCorrupted
            }
            let key = SymmetricKey(data: storedKey)
            let plaintext = try AES.GCM.open(box, using: key)
            guard let password = String(data: plaintext, encoding: .utf8) else {
                throw KeychainError.dataCorrupted
            }
            return password
        } catch let error as KeychainError {
            throw error
        } catch {
            throw KeychainError.dataCorrupted
        }
    }

    public func setRememberedPassword(_ password: String?) throws {
        lock.lock()
        defer { lock.unlock() }

        guard let password else {
            try delete(account: Self.rememberedPasswordAccount)
            return
        }
        guard let plaintext = password.data(using: .utf8) else {
            throw KeychainError.dataCorrupted
        }

        do {
            let key = SymmetricKey(data: try deviceKeyLocked())
            let sealed = try AES.GCM.seal(plaintext, using: key)
            guard let combined = sealed.combined else {
                throw KeychainError.dataCorrupted
            }
            var data = Data([Self.rememberedPasswordVersion])
            data.append(combined)
            try write(data, account: Self.rememberedPasswordAccount)
        } catch let error as KeychainError {
            throw error
        } catch {
            throw KeychainError.dataCorrupted
        }
    }

    // MARK: - Security framework plumbing

    /// Caller holds `lock`.
    private func deviceKeyLocked() throws -> Data {
        if let stored = try storedDeviceKey() {
            return stored
        }

        var bytes = [UInt8](repeating: 0, count: Self.deviceKeyByteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw KeychainError.randomGenerationFailed(status)
        }
        let key = Data(bytes)
        try write(key, account: Self.deviceKeyAccount)
        return key
    }

    /// Caller holds `lock`.
    private func setDeviceKeyLocked(_ key: Data) throws {
        guard key.count == Self.deviceKeyByteCount else {
            throw KeychainError.invalidKeyLength(
                expected: Self.deviceKeyByteCount, found: key.count
            )
        }
        try write(key, account: Self.deviceKeyAccount)
    }

    private func storedDeviceKey() throws -> Data? {
        guard let stored = try read(account: Self.deviceKeyAccount) else {
            return nil
        }
        guard stored.count == Self.deviceKeyByteCount else {
            throw KeychainError.invalidKeyLength(
                expected: Self.deviceKeyByteCount, found: stored.count
            )
        }
        return stored
    }

    private func baseQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if usesDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    private func read(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        guard let data = result as? Data else {
            throw KeychainError.dataCorrupted
        }
        return data
    }

    private func write(_ data: Data, account: String) throws {
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] =
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    private func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
#endif
