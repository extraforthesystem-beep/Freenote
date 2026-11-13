import Foundation

/// Reads and writes one page as a single `.page` file: JSON compressed with zlib.
public enum PageCodec {
    public static func encode(_ page: Page) throws -> Data {
        guard page.schemaVersion <= SchemaVersion.current else {
            throw NoteCoreError.unsupportedSchemaVersion(
                found: page.schemaVersion,
                supported: SchemaVersion.current
            )
        }
        let json: Data
        do {
            json = try NoteCoreJSON.encoder().encode(page)
        } catch {
            throw NoteCoreError.ioFailure("could not encode page \(page.id.uuidString): \(error)")
        }
        return try Zlib.compress(json, path: page.id.uuidString)
    }

    public static func decode(_ data: Data, path: String = "") throws -> Page {
        let json = try Zlib.decompress(data, path: path)
        try VersionGate.check(json, path: path)
        do {
            return try NoteCoreJSON.decoder().decode(Page.self, from: json)
        } catch {
            throw NoteCoreError.corruptFile(path: path)
        }
    }
}
