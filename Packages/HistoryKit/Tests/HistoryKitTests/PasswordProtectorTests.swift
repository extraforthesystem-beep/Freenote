import Foundation
import Testing
@testable import HistoryKit

@Suite("Password protector")
struct PasswordProtectorTests {
    private let password = "correct horse battery staple"

    @Test func roundTripPreservesBytes() throws {
        let samples: [Data] = [
            Data(),
            Data("hello".utf8),
            Data("héllo 世界 🖋️".utf8),
            Data(repeating: 0xAB, count: 4_096),
        ]

        for sample in samples {
            let blob = try PasswordProtector.seal(
                data: sample, password: password, iterations: 1_000
            )
            #expect(blob.iterations == 1_000)
            #expect(blob.salt.count == PasswordProtector.saltByteCount)
            #expect(blob.nonce.count == PasswordProtector.nonceByteCount)
            #expect(blob.tag.count == PasswordProtector.tagByteCount)

            let opened = try PasswordProtector.open(blob: blob, password: password)
            #expect(opened == sample)
        }
    }

    @Test func sealingTwiceUsesFreshSaltAndNonce() throws {
        let data = Data("same plaintext".utf8)
        let first = try PasswordProtector.seal(
            data: data, password: password, iterations: 1_000
        )
        let second = try PasswordProtector.seal(
            data: data, password: password, iterations: 1_000
        )

        #expect(first.salt != second.salt)
        #expect(first.nonce != second.nonce)
        #expect(first.ciphertext != second.ciphertext)

        #expect(try PasswordProtector.open(blob: first, password: password) == data)
        #expect(try PasswordProtector.open(blob: second, password: password) == data)
    }

    @Test func wrongPasswordThrowsTypedError() throws {
        let blob = try PasswordProtector.seal(
            data: Data("secret".utf8), password: password, iterations: 1_000
        )

        #expect(throws: PasswordProtectorError.wrongPassword) {
            _ = try PasswordProtector.open(blob: blob, password: "not the password")
        }
    }

    @Test func tamperedCiphertextFailsAuthentication() throws {
        let blob = try PasswordProtector.seal(
            data: Data("secret".utf8), password: password, iterations: 1_000
        )

        var tampered = blob
        tampered.ciphertext[tampered.ciphertext.startIndex] ^= 0x01

        #expect(throws: PasswordProtectorError.wrongPassword) {
            _ = try PasswordProtector.open(blob: tampered, password: password)
        }
    }

    @Test func tamperedTagFailsAuthentication() throws {
        let blob = try PasswordProtector.seal(
            data: Data("secret".utf8), password: password, iterations: 1_000
        )

        var tampered = blob
        tampered.tag[tampered.tag.startIndex] ^= 0x01

        #expect(throws: PasswordProtectorError.wrongPassword) {
            _ = try PasswordProtector.open(blob: tampered, password: password)
        }
    }

    @Test func tamperedSaltAndNonceFailAuthentication() throws {
        let blob = try PasswordProtector.seal(
            data: Data("secret".utf8), password: password, iterations: 1_000
        )

        var saltChanged = blob
        saltChanged.salt[saltChanged.salt.startIndex] ^= 0x01
        #expect(throws: PasswordProtectorError.wrongPassword) {
            _ = try PasswordProtector.open(blob: saltChanged, password: password)
        }

        var nonceChanged = blob
        nonceChanged.nonce[nonceChanged.nonce.startIndex] ^= 0x01
        #expect(throws: PasswordProtectorError.wrongPassword) {
            _ = try PasswordProtector.open(blob: nonceChanged, password: password)
        }
    }

    @Test func malformedShapesAreRejectedBeforeDecryption() throws {
        let blob = try PasswordProtector.seal(
            data: Data("secret".utf8), password: password, iterations: 1_000
        )

        var shortTag = blob
        shortTag.tag = Data(shortTag.tag.dropLast())
        #expect(throws: PasswordProtectorError.self) {
            _ = try PasswordProtector.open(blob: shortTag, password: password)
        }

        var shortNonce = blob
        shortNonce.nonce = Data(shortNonce.nonce.dropLast())
        #expect(throws: PasswordProtectorError.self) {
            _ = try PasswordProtector.open(blob: shortNonce, password: password)
        }

        var shortSalt = blob
        shortSalt.salt = Data(shortSalt.salt.prefix(4))
        #expect(throws: PasswordProtectorError.self) {
            _ = try PasswordProtector.open(blob: shortSalt, password: password)
        }
    }

    @Test func iterationCountsAreBounded() throws {
        #expect(throws: PasswordProtectorError.unsupportedIterations(10)) {
            _ = try PasswordProtector.seal(
                data: Data(), password: password, iterations: 10
            )
        }

        var blob = try PasswordProtector.seal(
            data: Data("x".utf8), password: password, iterations: 1_000
        )
        blob.iterations = 0
        #expect(throws: PasswordProtectorError.unsupportedIterations(0)) {
            _ = try PasswordProtector.open(blob: blob, password: password)
        }
    }

    @Test func emptyPasswordIsRefused() {
        #expect(throws: PasswordProtectorError.emptyPassword) {
            _ = try PasswordProtector.seal(data: Data(), password: "", iterations: 1_000)
        }

        let blob = SealedBlob(
            salt: Data(repeating: 0, count: 16),
            nonce: Data(repeating: 0, count: 12),
            ciphertext: Data(),
            tag: Data(repeating: 0, count: 16),
            iterations: 1_000
        )
        #expect(throws: PasswordProtectorError.emptyPassword) {
            _ = try PasswordProtector.open(blob: blob, password: "")
        }
    }

    @Test func defaultIterationsAreRecordedAndUsable() throws {
        let data = Data("default".utf8)
        let blob = try PasswordProtector.seal(data: data, password: password)
        #expect(blob.iterations == PasswordProtector.defaultIterations)

        let opened = try PasswordProtector.open(blob: blob, password: password)
        #expect(opened == data)
    }

    @Test func sealedBlobIsCodable() throws {
        let data = Data("codable".utf8)
        let blob = try PasswordProtector.seal(
            data: data, password: password, iterations: 1_000
        )

        let encoded = try JSONEncoder().encode(blob)
        let decoded = try JSONDecoder().decode(SealedBlob.self, from: encoded)
        #expect(decoded == blob)

        let opened = try PasswordProtector.open(blob: decoded, password: password)
        #expect(opened == data)
    }

    @Test func ciphertextDoesNotContainThePlaintext() throws {
        let marker = "TOP-SECRET-MARKER-\(UUID().uuidString)"
        let blob = try PasswordProtector.seal(
            data: Data(marker.utf8), password: password, iterations: 1_000
        )

        #expect(blob.ciphertext.range(of: Data(marker.utf8)) == nil)
        #expect(blob.salt.range(of: Data(marker.utf8)) == nil)
    }
}
