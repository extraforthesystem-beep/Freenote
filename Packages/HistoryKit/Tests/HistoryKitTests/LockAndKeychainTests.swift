import Foundation
import Testing
@testable import HistoryKit

@Suite("Lock policy")
struct LockPolicyTests {
    @Test func defaultsMatchTheDocumentedValues() {
        let policy = LockPolicy()
        #expect(policy.autoLockMinutes == 5)
        #expect(policy.lockOnBackground)
        #expect(policy.hideFromSearch)
    }

    @Test func locksAfterTheIdleInterval() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let policy = LockPolicy(
            autoLockMinutes: 5, lockOnBackground: true, hideFromSearch: true
        )

        #expect(
            !LockPolicy.shouldLock(
                lastUnlock: now.addingTimeInterval(-299), now: now, policy: policy
            )
        )
        #expect(
            LockPolicy.shouldLock(
                lastUnlock: now.addingTimeInterval(-300), now: now, policy: policy
            )
        )
        #expect(
            LockPolicy.shouldLock(
                lastUnlock: now.addingTimeInterval(-301), now: now, policy: policy
            )
        )
    }

    @Test func zeroMinutesDisablesIdleLocking() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let policy = LockPolicy(autoLockMinutes: 0)

        #expect(
            !LockPolicy.shouldLock(
                lastUnlock: now.addingTimeInterval(-86_400), now: now, policy: policy
            )
        )
        #expect(
            !LockPolicy.shouldLock(lastUnlock: nil, now: now, policy: policy)
        )
    }

    @Test func neverUnlockedIsLocked() {
        let policy = LockPolicy()
        #expect(
            LockPolicy.shouldLock(
                lastUnlock: nil, now: Date(timeIntervalSince1970: 1_700_000_000),
                policy: policy
            )
        )
    }

    @Test func aFutureUnlockDoesNotLock() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let policy = LockPolicy(autoLockMinutes: 5)

        // A backwards clock change must not lock a notebook the user just opened.
        #expect(
            !LockPolicy.shouldLock(
                lastUnlock: now.addingTimeInterval(3_600), now: now, policy: policy
            )
        )
    }

    @Test func codableUsesDefaultsForMissingFields() throws {
        let policy = LockPolicy(
            autoLockMinutes: 30, lockOnBackground: false, hideFromSearch: false
        )
        let encoded = try JSONEncoder().encode(policy)
        let decoded = try JSONDecoder().decode(LockPolicy.self, from: encoded)
        #expect(decoded == policy)

        let partial = Data(#"{"autoLockMinutes":30}"#.utf8)
        let defaults = try JSONDecoder().decode(LockPolicy.self, from: partial)
        #expect(defaults.autoLockMinutes == 30)
        #expect(defaults.lockOnBackground)
        #expect(defaults.hideFromSearch)
    }
}

@Suite("Keychain key store protocol")
struct KeychainKeyStoreTests {
    @Test func deviceKeyIsCreatedOnceAndStaysStable() throws {
        let store = InMemoryKeychainKeyStore()

        let first = try store.deviceKey()
        let second = try store.deviceKey()

        #expect(first.count == 32)
        #expect(first == second)
    }

    @Test func aStoredDeviceKeyIsReturned() throws {
        let store = InMemoryKeychainKeyStore()
        let key = Data(repeating: 0x42, count: 32)

        try store.setDeviceKey(key)
        #expect(try store.deviceKey() == key)
    }

    @Test func deviceKeyLengthIsValidated() {
        let store = InMemoryKeychainKeyStore()

        #expect(throws: KeychainError.invalidKeyLength(expected: 32, found: 4)) {
            try store.setDeviceKey(Data(repeating: 0, count: 4))
        }
    }

    @Test func rememberedPasswordCanBeSetAndCleared() throws {
        let store = InMemoryKeychainKeyStore()
        #expect(try store.rememberedPassword() == nil)

        try store.setRememberedPassword("open sesame")
        #expect(try store.rememberedPassword() == "open sesame")

        try store.setRememberedPassword(nil)
        #expect(try store.rememberedPassword() == nil)
    }
}

/// A lock-guarded in-memory implementation used by the protocol tests.
private final class InMemoryKeychainKeyStore: KeychainKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var key: Data?
    private var password: String?

    init(key: Data? = nil, password: String? = nil) {
        self.key = key
        self.password = password
    }

    func deviceKey() throws -> Data {
        lock.lock()
        defer { lock.unlock() }

        if let key { return key }
        var generator = SystemRandomNumberGenerator()
        let generated = Data(
            (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        )
        self.key = generated
        return generated
    }

    func setDeviceKey(_ key: Data) throws {
        guard key.count == 32 else {
            throw KeychainError.invalidKeyLength(expected: 32, found: key.count)
        }
        lock.lock()
        defer { lock.unlock() }
        self.key = key
    }

    func rememberedPassword() throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return password
    }

    func setRememberedPassword(_ password: String?) throws {
        lock.lock()
        defer { lock.unlock() }
        self.password = password
    }
}
