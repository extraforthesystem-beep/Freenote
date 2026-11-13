import Compression
import Foundation

/// Deterministic JSON: sorted keys, so that the same value always produces the
/// same bytes, and ISO-8601 dates.
enum NoteCoreJSON {
    static func encoder(prettyPrinted: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.sortedKeys, .prettyPrinted] : [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISODate.string(from: date))
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            return try ISODate.date(from: text)
        }
        return decoder
    }
}

/// zlib compression for page files.
enum Zlib {
    private static let maximumDecompressedSize = 512 * 1_024 * 1_024

    static func compress(_ input: Data, path: String) throws -> Data {
        guard !input.isEmpty else { return Data() }

        var capacity = input.count + input.count / 64 + 1_024
        while capacity <= maximumDecompressedSize {
            var output = Data(count: capacity)
            let written: Int? = output.withUnsafeMutableBytes { destination in
                guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress else {
                    return nil
                }
                return input.withUnsafeBytes { source in
                    guard let sourceBase = source.bindMemory(to: UInt8.self).baseAddress else {
                        return nil
                    }
                    return compression_encode_buffer(
                        destinationBase,
                        capacity,
                        sourceBase,
                        input.count,
                        nil,
                        COMPRESSION_ZLIB
                    )
                }
            }
            // A full destination can come back as a partial write rather than 0 on
            // some SDKs, so a write that fills the buffer is a retry, not success.
            if let written, written > 0, written < capacity {
                return output.prefix(written)
            }
            capacity *= 2
        }
        throw NoteCoreError.ioFailure("could not compress \(path.isEmpty ? "data" : path)")
    }

    static func decompress(_ input: Data, path: String) throws -> Data {
        guard !input.isEmpty else { throw NoteCoreError.corruptFile(path: path) }

        var capacity = max(4_096, input.count * 8)
        while capacity <= maximumDecompressedSize {
            var output = Data(count: capacity)
            let written: Int? = output.withUnsafeMutableBytes { destination in
                guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress else {
                    return nil
                }
                return input.withUnsafeBytes { source in
                    guard let sourceBase = source.bindMemory(to: UInt8.self).baseAddress else {
                        return nil
                    }
                    return compression_decode_buffer(
                        destinationBase,
                        capacity,
                        sourceBase,
                        input.count,
                        nil,
                        COMPRESSION_ZLIB
                    )
                }
            }
            // A full destination can come back as a partial write rather than 0 on
            // some SDKs, so a write that fills the buffer is a retry, not success.
            if let written, written > 0, written < capacity {
                return output.prefix(written)
            }
            capacity *= 2
        }
        throw NoteCoreError.corruptFile(path: path)
    }
}

/// Refuses a file whose `schemaVersion` is newer than this build, before anything
/// else in the file is decoded.
enum VersionGate {
    private struct Probe: Decodable {
        /// Absent on files written before the format carried a version.
        let schemaVersion: Int?
    }

    static func check(_ data: Data, path: String) throws {
        let probe: Probe
        do {
            probe = try NoteCoreJSON.decoder().decode(Probe.self, from: data)
        } catch {
            throw NoteCoreError.corruptFile(path: path)
        }
        let version = probe.schemaVersion ?? SchemaVersion.initial
        guard version <= SchemaVersion.current else {
            throw NoteCoreError.unsupportedSchemaVersion(
                found: version,
                supported: SchemaVersion.current
            )
        }
    }
}

/// Plain, pretty-printed JSON documents: the manifest, the folder tree and the
/// library info.
enum JSONDocument {
    static func encode<T: Encodable>(_ value: T, path: String) throws -> Data {
        do {
            return try NoteCoreJSON.encoder(prettyPrinted: true).encode(value)
        } catch {
            throw NoteCoreError.ioFailure("could not encode \(path): \(error)")
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data, path: String) throws -> T {
        try VersionGate.check(data, path: path)
        do {
            return try NoteCoreJSON.decoder().decode(type, from: data)
        } catch {
            throw NoteCoreError.corruptFile(path: path)
        }
    }
}
