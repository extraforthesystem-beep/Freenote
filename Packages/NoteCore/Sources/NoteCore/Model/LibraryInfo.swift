import Foundation

/// Root metadata of a library, stored as `library.json`.
public struct LibraryInfo: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    /// Identifies the device that created this library, for later sync bookkeeping.
    public var deviceID: UUID

    public init(schemaVersion: Int = SchemaVersion.current, deviceID: UUID) {
        self.schemaVersion = schemaVersion
        self.deviceID = deviceID
    }
}
