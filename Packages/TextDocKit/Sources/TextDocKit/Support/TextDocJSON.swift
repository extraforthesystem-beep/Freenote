import Foundation

/// JSON coding for text documents.
///
/// Keys are sorted so the same value always produces the same bytes. Dates are
/// stored as seconds since Apple's 2001 reference date (`Double`) rather than
/// formatted text or Unix seconds: both of those conversions round twice and can
/// move a `Date` by one unit in the last place. The reference interval preserves
/// the exact value across a round trip.
enum TextDocJSON {
    /// A deterministic encoder, optionally pretty-printed.
    static func encoder(prettyPrinted: Bool = true) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.sortedKeys, .prettyPrinted] : [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSinceReferenceDate)
        }
        return encoder
    }

    /// A decoder matching ``encoder(prettyPrinted:)``.
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let seconds = try container.decode(Double.self)
            return Date(timeIntervalSinceReferenceDate: seconds)
        }
        return decoder
    }

    /// Encodes a document, mapping failures to ``TextDocError/ioFailure(_:)``.
    static func encode<T: Encodable>(_ value: T, path: String) throws -> Data {
        do {
            return try encoder().encode(value)
        } catch {
            throw TextDocError.ioFailure("could not encode \(path): \(error)")
        }
    }

    /// Decodes a document, refusing an unsupported schema before decoding its body.
    static func decodeDocument(from data: Data, path: String) throws -> TextDocument {
        let probe: SchemaProbe
        do {
            probe = try decoder().decode(SchemaProbe.self, from: data)
        } catch {
            throw TextDocError.corruptFile(path: path)
        }
        guard probe.schemaVersion >= 1 else {
            throw TextDocError.corruptFile(path: path)
        }
        guard probe.schemaVersion <= TextDocument.currentSchemaVersion else {
            throw TextDocError.unsupportedSchemaVersion(
                found: probe.schemaVersion,
                supported: TextDocument.currentSchemaVersion
            )
        }
        do {
            return try decoder().decode(TextDocument.self, from: data)
        } catch {
            throw TextDocError.corruptFile(path: path)
        }
    }

    /// The only field read before the full document is decoded.
    private struct SchemaProbe: Decodable {
        let schemaVersion: Int
    }
}
