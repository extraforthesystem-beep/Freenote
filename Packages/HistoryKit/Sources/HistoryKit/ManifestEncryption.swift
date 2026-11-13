import Foundation

/// Errors from the locked-manifest envelope.
public enum ManifestEncryptionError: Error, Hashable, Sendable {
    /// The bytes do not start with the locked-manifest magic.
    case notAnEnvelope
    /// The envelope was written by a newer format than this build understands.
    case unsupportedVersion(found: UInt8, supported: UInt8)
    /// The envelope header or encrypted payload is malformed.
    case corruptEnvelope(String)
    /// The password is wrong, or the envelope was changed.
    case wrongPassword
    /// The file system refused an operation.
    case ioFailure(String)
}

extension ManifestEncryptionError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notAnEnvelope:
            "This file is not a locked manifest."
        case let .unsupportedVersion(found, supported):
            "Locked manifest version \(found) is newer than the supported version \(supported)."
        case let .corruptEnvelope(reason):
            "Locked manifest is unreadable: \(reason)"
        case .wrongPassword:
            "The password is wrong, or the locked manifest was changed."
        case let .ioFailure(reason):
            "File system error: \(reason)"
        }
    }
}

/// Encrypts a JSON manifest into a small self-describing envelope.
///
/// The envelope starts with the four magic bytes `NHLK` and one version byte,
/// followed by the JSON-encoded `SealedBlob`. A reader can therefore tell that a
/// notebook is locked from the first five bytes alone, without deriving a key or
/// touching the ciphertext. Everything after the header is authenticated
/// AES-GCM, so a changed version byte, blob or manifest fails `open`.
public enum ManifestEncryption {
    /// Magic bytes at the start of every locked manifest: `NHLK`.
    public static let envelopeMagic: [UInt8] = [0x4E, 0x48, 0x4C, 0x4B]
    /// The only envelope version this build writes.
    public static let currentVersion: UInt8 = 1
    /// Suggested file extension for a locked manifest.
    public static let fileExtension = "lockedmanifest"

    /// Encrypts a Codable manifest and returns the complete envelope bytes.
    public static func seal<T: Encodable>(
        _ manifest: T,
        password: String,
        iterations: Int = PasswordProtector.defaultIterations
    ) throws -> Data {
        let json: Data
        do {
            json = try HistoryJSON.encoder().encode(manifest)
        } catch {
            throw ManifestEncryptionError.corruptEnvelope(
                "could not encode the manifest: \(error)"
            )
        }

        let blob = try PasswordProtector.seal(
            data: json, password: password, iterations: iterations
        )
        let blobData: Data
        do {
            blobData = try HistoryJSON.encoder().encode(blob)
        } catch {
            throw ManifestEncryptionError.corruptEnvelope(
                "could not encode the sealed blob: \(error)"
            )
        }

        var envelope = Data(envelopeMagic)
        envelope.append(currentVersion)
        envelope.append(blobData)
        return envelope
    }

    /// Decrypts an envelope and decodes the manifest inside it.
    ///
    /// Throws `ManifestEncryptionError.wrongPassword` for a wrong password or any
    /// changed byte; no partial manifest is returned.
    public static func open<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        password: String
    ) throws -> T {
        guard isEnvelope(data) else {
            throw ManifestEncryptionError.notAnEnvelope
        }

        let versionIndex = data.index(data.startIndex, offsetBy: envelopeMagic.count)
        let version = data[versionIndex]
        guard version == currentVersion else {
            throw ManifestEncryptionError.unsupportedVersion(
                found: version, supported: currentVersion
            )
        }

        let blobData = Data(data.dropFirst(envelopeMagic.count + 1))
        let blob: SealedBlob
        do {
            blob = try HistoryJSON.decoder().decode(SealedBlob.self, from: blobData)
        } catch {
            throw ManifestEncryptionError.corruptEnvelope("sealed blob is unreadable")
        }

        let json: Data
        do {
            json = try PasswordProtector.open(blob: blob, password: password)
        } catch let error as PasswordProtectorError {
            if error == .wrongPassword {
                throw ManifestEncryptionError.wrongPassword
            }
            throw ManifestEncryptionError.corruptEnvelope(error.description)
        }

        do {
            return try HistoryJSON.decoder().decode(type, from: json)
        } catch {
            throw ManifestEncryptionError.corruptEnvelope("manifest is unreadable")
        }
    }

    /// True when `data` starts with the locked-manifest magic and a version byte.
    ///
    /// This checks the header only; it does not prove the ciphertext is valid.
    public static func isEnvelope(_ data: Data) -> Bool {
        data.count >= envelopeMagic.count + 1
            && data.prefix(envelopeMagic.count).elementsEqual(envelopeMagic)
    }

    /// True when the file at `url` is a locked manifest. Missing files are `false`.
    ///
    /// Only the five header bytes are read, so a locked notebook can be detected
    /// without decrypting it or loading the payload into memory.
    public static func isEncryptedManifest(at url: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw ManifestEncryptionError.ioFailure(
                "could not open \(url.lastPathComponent): \(error)"
            )
        }
        defer { try? handle.close() }

        let header: Data
        do {
            header = try handle.read(upToCount: envelopeMagic.count + 1) ?? Data()
        } catch {
            throw ManifestEncryptionError.ioFailure(
                "could not read \(url.lastPathComponent): \(error)"
            )
        }
        return isEnvelope(header)
    }

    /// Encrypts a manifest and writes the envelope atomically to `url`.
    public static func write<T: Encodable>(
        _ manifest: T,
        password: String,
        to url: URL,
        iterations: Int = PasswordProtector.defaultIterations
    ) throws {
        let data = try seal(manifest, password: password, iterations: iterations)
        do {
            try AtomicFile.write(data, to: url)
        } catch {
            throw ManifestEncryptionError.ioFailure(
                "could not write locked manifest: \(error)"
            )
        }
    }

    /// Reads and decrypts a manifest previously written by `write`.
    public static func read<T: Decodable>(
        _ type: T.Type,
        from url: URL,
        password: String
    ) throws -> T {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ManifestEncryptionError.ioFailure(
                "could not read locked manifest: \(error)"
            )
        }
        return try open(type, from: data, password: password)
    }
}
