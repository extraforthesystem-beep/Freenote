import CryptoKit
import Foundation

#if canImport(CommonCrypto)
import CommonCrypto
#endif

/// Errors from `PasswordProtector`.
public enum PasswordProtectorError: Error, Hashable, Sendable {
    /// AES-GCM authentication failed: the password is wrong, or the blob was changed.
    case wrongPassword
    /// The blob's salt, nonce, tag or iteration count is not usable.
    case invalidBlob(String)
    /// The iteration count is outside the supported range.
    case unsupportedIterations(Int)
    /// An empty password is refused rather than silently accepted.
    case emptyPassword
    /// PBKDF2 is not available on this platform.
    case keyDerivationUnavailable
    /// PBKDF2 returned an error.
    case keyDerivationFailed(Int32)
    /// AES-GCM could not seal the data.
    case encryptionFailed(String)
}

extension PasswordProtectorError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .wrongPassword:
            "The password is wrong, or the encrypted data was changed."
        case let .invalidBlob(reason):
            "The encrypted blob is invalid: \(reason)"
        case let .unsupportedIterations(iterations):
            "PBKDF2 iteration count \(iterations) is outside the supported range."
        case .emptyPassword:
            "The password must not be empty."
        case .keyDerivationUnavailable:
            "PBKDF2 is not available on this platform."
        case let .keyDerivationFailed(status):
            "PBKDF2 failed with status \(status)."
        case let .encryptionFailed(reason):
            "AES-GCM encryption failed: \(reason)"
        }
    }
}

/// An AES-GCM ciphertext plus everything needed to derive its key again.
///
/// `iterations` is stored with the blob so a future change to the default does
/// not make old history unreadable. All fields are `Data`, which encodes as
/// base64 in JSON.
public struct SealedBlob: Codable, Hashable, Sendable {
    /// Random PBKDF2 salt. `PasswordProtector` writes 16 bytes.
    public var salt: Data
    /// AES-GCM nonce. Always 12 bytes.
    public var nonce: Data
    /// Encrypted bytes.
    public var ciphertext: Data
    /// AES-GCM authentication tag. Always 16 bytes.
    public var tag: Data
    /// PBKDF2-HMAC-SHA256 rounds used to derive the key.
    public var iterations: Int

    /// Creates a blob from an existing ciphertext; `seal` is the usual producer.
    public init(
        salt: Data,
        nonce: Data,
        ciphertext: Data,
        tag: Data,
        iterations: Int
    ) {
        self.salt = salt
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.tag = tag
        self.iterations = iterations
    }
}

/// Password-based authenticated encryption for notebooks and manifests.
///
/// The key is PBKDF2-HMAC-SHA256 (CommonCrypto) with a fresh 16-byte salt and a
/// high iteration count. Encryption is AES-256-GCM, so a wrong password or any
/// changed byte fails authentication and `open` throws instead of returning
/// partial data.
public enum PasswordProtector {
    /// 210,000 PBKDF2 rounds, used when the caller does not choose a count.
    public static let defaultIterations = 210_000
    /// Lower bound accepted by `seal` and `open`.
    public static let minimumIterations = 1_000
    /// Upper bound accepted by `seal` and `open`; protects against a hostile blob
    /// asking for an unbounded amount of work.
    public static let maximumIterations = 10_000_000
    /// Salt length written by `seal`.
    public static let saltByteCount = 16
    /// AES-GCM nonce length.
    public static let nonceByteCount = 12
    /// AES-GCM tag length.
    public static let tagByteCount = 16

    /// Encrypts `data` with a key derived from `password`.
    public static func seal(
        data: Data,
        password: String,
        iterations: Int = defaultIterations
    ) throws -> SealedBlob {
        guard !password.isEmpty else { throw PasswordProtectorError.emptyPassword }
        try validate(iterations: iterations)

        let salt = randomSalt()
        let key = try deriveKey(password: password, salt: salt, iterations: iterations)
        let nonce = AES.GCM.Nonce()

        do {
            let sealed = try AES.GCM.seal(data, using: key, nonce: nonce)
            return SealedBlob(
                salt: salt,
                nonce: Data(nonce),
                ciphertext: sealed.ciphertext,
                tag: sealed.tag,
                iterations: iterations
            )
        } catch {
            throw PasswordProtectorError.encryptionFailed("\(error)")
        }
    }

    /// Decrypts `blob` and verifies its authentication tag.
    ///
    /// Throws `PasswordProtectorError.wrongPassword` for a wrong password or any
    /// tampering; no partial plaintext is ever returned.
    public static func open(blob: SealedBlob, password: String) throws -> Data {
        guard !password.isEmpty else { throw PasswordProtectorError.emptyPassword }
        try validate(iterations: blob.iterations)
        guard blob.salt.count >= saltByteCount else {
            throw PasswordProtectorError.invalidBlob("salt is shorter than \(saltByteCount) bytes")
        }
        guard blob.nonce.count == nonceByteCount else {
            throw PasswordProtectorError.invalidBlob("nonce must be \(nonceByteCount) bytes")
        }
        guard blob.tag.count == tagByteCount else {
            throw PasswordProtectorError.invalidBlob("tag must be \(tagByteCount) bytes")
        }

        let key = try deriveKey(
            password: password, salt: blob.salt, iterations: blob.iterations
        )

        do {
            let nonce = try AES.GCM.Nonce(data: blob.nonce)
            let box = try AES.GCM.SealedBox(
                nonce: nonce, ciphertext: blob.ciphertext, tag: blob.tag
            )
            return try AES.GCM.open(box, using: key)
        } catch {
            if let cryptoError = error as? CryptoKitError,
               case .authenticationFailure = cryptoError {
                throw PasswordProtectorError.wrongPassword
            }
            throw PasswordProtectorError.invalidBlob("\(error)")
        }
    }

    // MARK: - Key derivation

    private static func validate(iterations: Int) throws {
        guard iterations >= minimumIterations, iterations <= maximumIterations else {
            throw PasswordProtectorError.unsupportedIterations(iterations)
        }
    }

    private static func randomSalt() -> Data {
        SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
    }

    #if canImport(CommonCrypto)
    private static func deriveKey(
        password: String,
        salt: Data,
        iterations: Int
    ) throws -> SymmetricKey {
        let passwordBytes = Data(password.utf8)
        var derived = Data(repeating: 0, count: 32)

        let status: Int32 = derived.withUnsafeMutableBytes { derivedBuffer in
            passwordBytes.withUnsafeBytes { passwordBuffer in
                salt.withUnsafeBytes { saltBuffer in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBuffer.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordBuffer.count,
                        saltBuffer.bindMemory(to: UInt8.self).baseAddress,
                        saltBuffer.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedBuffer.bindMemory(to: UInt8.self).baseAddress,
                        derivedBuffer.count
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw PasswordProtectorError.keyDerivationFailed(status)
        }
        return SymmetricKey(data: derived)
    }
    #else
    private static func deriveKey(
        password: String,
        salt: Data,
        iterations: Int
    ) throws -> SymmetricKey {
        throw PasswordProtectorError.keyDerivationUnavailable
    }
    #endif
}
