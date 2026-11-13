import Foundation
import Testing
@testable import HistoryKit

@Suite("Manifest encryption")
struct ManifestEncryptionTests {
    private struct SampleManifest: Codable, Equatable, Sendable {
        var title: String
        var pageOrder: [UUID]
        var updatedAt: Date
    }

    private func makeManifest(title: String = "Journal") -> SampleManifest {
        SampleManifest(
            title: title,
            pageOrder: [UUID(), UUID()],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000.123_456)
        )
    }

    @Test func envelopeRoundTrips() throws {
        let manifest = makeManifest()
        let data = try ManifestEncryption.seal(
            manifest, password: "pw", iterations: 1_000
        )

        #expect(ManifestEncryption.isEnvelope(data))
        let versionIndex = data.index(data.startIndex, offsetBy: 4)
        #expect(data[versionIndex] == ManifestEncryption.currentVersion)
        #expect(data.prefix(4).elementsEqual(ManifestEncryption.envelopeMagic))

        let opened = try ManifestEncryption.open(
            SampleManifest.self, from: data, password: "pw"
        )
        #expect(opened == manifest)
    }

    @Test func plainJSONIsNotAnEnvelope() throws {
        let manifest = makeManifest()
        let data = try JSONEncoder().encode(manifest)

        #expect(!ManifestEncryption.isEnvelope(data))
        #expect(throws: ManifestEncryptionError.notAnEnvelope) {
            _ = try ManifestEncryption.open(
                SampleManifest.self, from: data, password: "pw"
            )
        }
    }

    @Test func wrongPasswordThrowsManifestError() throws {
        let data = try ManifestEncryption.seal(
            makeManifest(), password: "right", iterations: 1_000
        )

        #expect(throws: ManifestEncryptionError.wrongPassword) {
            _ = try ManifestEncryption.open(
                SampleManifest.self, from: data, password: "wrong"
            )
        }
    }

    @Test func tamperingIsRejected() throws {
        let sealed = try ManifestEncryption.seal(
            makeManifest(), password: "pw", iterations: 1_000
        )
        var blob = try JSONDecoder().decode(
            SealedBlob.self, from: Data(sealed.dropFirst(5))
        )
        blob.ciphertext[blob.ciphertext.startIndex] ^= 0x01

        var tampered = Data(ManifestEncryption.envelopeMagic)
        tampered.append(ManifestEncryption.currentVersion)
        tampered.append(try JSONEncoder().encode(blob))

        #expect(ManifestEncryption.isEnvelope(tampered))
        #expect(throws: ManifestEncryptionError.wrongPassword) {
            _ = try ManifestEncryption.open(
                SampleManifest.self, from: tampered, password: "pw"
            )
        }
    }

    @Test func unsupportedVersionIsDetectedWithoutDecrypting() throws {
        var data = try ManifestEncryption.seal(
            makeManifest(), password: "pw", iterations: 1_000
        )
        data[data.index(data.startIndex, offsetBy: 4)] = 99

        #expect(ManifestEncryption.isEnvelope(data))
        #expect(
            throws: ManifestEncryptionError.unsupportedVersion(
                found: 99, supported: ManifestEncryption.currentVersion
            )
        ) {
            _ = try ManifestEncryption.open(
                SampleManifest.self, from: data, password: "pw"
            )
        }
    }

    @Test func corruptBlobIsReportedAsCorruptEnvelope() throws {
        var data = try ManifestEncryption.seal(
            makeManifest(), password: "pw", iterations: 1_000
        )
        data = data.prefix(8)

        #expect(ManifestEncryption.isEnvelope(data))
        #expect(throws: ManifestEncryptionError.self) {
            _ = try ManifestEncryption.open(
                SampleManifest.self, from: data, password: "pw"
            )
        }
    }

    @Test func writesDetectsAndReadsAFile() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let manifest = makeManifest(title: "Locked notebook")
        let url = root.appendingPathComponent(
            "notebook.\(ManifestEncryption.fileExtension)"
        )
        try ManifestEncryption.write(
            manifest, password: "pw", to: url, iterations: 1_000
        )

        let detected = try ManifestEncryption.isEncryptedManifest(at: url)
        #expect(detected)

        let opened = try ManifestEncryption.read(
            SampleManifest.self, from: url, password: "pw"
        )
        #expect(opened == manifest)
    }

    @Test func plainAndMissingFilesAreNotLocked() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let plainURL = root.appendingPathComponent("notebook.json")
        try JSONEncoder().encode(makeManifest()).write(to: plainURL)
        let plainDetected = try ManifestEncryption.isEncryptedManifest(at: plainURL)
        #expect(!plainDetected)

        let missingURL = root.appendingPathComponent("missing.lockedmanifest")
        let missingDetected = try ManifestEncryption.isEncryptedManifest(at: missingURL)
        #expect(!missingDetected)
    }

    @Test func envelopeDoesNotLeakTheManifest() throws {
        let marker = "CONFIDENTIAL-\(UUID().uuidString)"
        let data = try ManifestEncryption.seal(
            makeManifest(title: marker), password: "pw", iterations: 1_000
        )

        #expect(data.range(of: Data(marker.utf8)) == nil)
    }

    @Test func fileWriteIsAtomic() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let url = root.appendingPathComponent("notebook.lockedmanifest")
        try ManifestEncryption.write(
            makeManifest(title: "first"), password: "pw", to: url, iterations: 1_000
        )
        try ManifestEncryption.write(
            makeManifest(title: "second"), password: "pw", to: url, iterations: 1_000
        )

        let opened = try ManifestEncryption.read(
            SampleManifest.self, from: url, password: "pw"
        )
        #expect(opened.title == "second")

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.hasPrefix(".tmp-") }
        #expect(leftovers.isEmpty)
    }
}
