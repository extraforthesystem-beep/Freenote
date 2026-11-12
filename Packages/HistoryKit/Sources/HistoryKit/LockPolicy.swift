import Foundation

/// How long an unlocked notebook stays open, and what locking hides.
public struct LockPolicy: Codable, Hashable, Sendable {
    /// Idle minutes before the notebook locks. Zero or less disables idle locking.
    public var autoLockMinutes: Int
    /// Lock as soon as the app leaves the foreground.
    public var lockOnBackground: Bool
    /// Keep the notebook out of search results while it is locked.
    public var hideFromSearch: Bool

    /// Creates a policy; every argument defaults to the documented value.
    public init(
        autoLockMinutes: Int = 5,
        lockOnBackground: Bool = true,
        hideFromSearch: Bool = true
    ) {
        self.autoLockMinutes = autoLockMinutes
        self.lockOnBackground = lockOnBackground
        self.hideFromSearch = hideFromSearch
    }

    /// The documented defaults: five idle minutes, lock on background, hide from search.
    public static let `default` = LockPolicy()

    /// Decodes missing fields as the defaults so a policy written by an older
    /// build keeps working after a field is added.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoLockMinutes = try container.decodeIfPresent(
            Int.self, forKey: .autoLockMinutes
        ) ?? 5
        lockOnBackground = try container.decodeIfPresent(
            Bool.self, forKey: .lockOnBackground
        ) ?? true
        hideFromSearch = try container.decodeIfPresent(
            Bool.self, forKey: .hideFromSearch
        ) ?? true
    }

    /// True when the idle timer has expired.
    ///
    /// `lastUnlock == nil` means the notebook has never been unlocked in this
    /// process, so it is locked. A timestamp in the future (a clock change) does
    /// not lock it. Background locking is a separate check on `lockOnBackground`
    /// because this function has no scene information.
    public static func shouldLock(
        lastUnlock: Date?,
        now: Date,
        policy: LockPolicy
    ) -> Bool {
        guard policy.autoLockMinutes > 0 else { return false }
        guard let lastUnlock else { return true }

        let elapsed = now.timeIntervalSince(lastUnlock)
        guard elapsed >= 0 else { return false }
        return elapsed >= Double(policy.autoLockMinutes) * 60
    }

    private enum CodingKeys: String, CodingKey {
        case autoLockMinutes
        case lockOnBackground
        case hideFromSearch
    }
}
