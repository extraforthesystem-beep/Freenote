import Foundation

/// Why an on-device model cannot answer right now.
public enum AIUnavailableReason: String, Codable, Equatable, Sendable, CaseIterable {
    /// The hardware does not support Apple Intelligence.
    case deviceNotEligible
    /// Apple Intelligence is supported but has not been turned on.
    case appleIntelligenceNotEnabled
    /// The model exists but is still downloading or preparing.
    case modelNotReady
    /// The running OS has no on-device language model.
    case unsupportedOS
    /// The system reported a reason this version of AIKit does not know.
    case unknown
}

/// Whether the on-device model can answer on this device.
public enum AIAvailability: Codable, Equatable, Sendable {
    /// The model is ready.
    case available
    /// The platform supports the model but it cannot be used for `reason`.
    case unavailable(reason: AIUnavailableReason)
    /// The running OS has no on-device language model.
    case unsupportedOS

    /// True only when the model is ready to answer.
    public var isAvailable: Bool {
        self == .available
    }

    /// The reason the model is unavailable, or nil when it is available.
    public var reason: AIUnavailableReason? {
        switch self {
        case .available:
            return nil
        case .unavailable(let reason):
            return reason
        case .unsupportedOS:
            return .unsupportedOS
        }
    }
}

/// What a provider can do on this device.
public protocol AICapabilityReporting: Sendable {
    /// Whether the provider can answer right now.
    var availability: AIAvailability { get }
    /// Whether the provider is ready; derived from `availability`.
    var isAvailable: Bool { get }
    /// The number of tokens the model can hold, including prompt and answer.
    var contextSize: Int { get }
    /// Languages the model handles best; empty means no advertised restriction.
    var supportedLanguages: [Locale.Language] { get }
}

extension AICapabilityReporting {
    /// Whether the provider is ready; derived from `availability`.
    public var isAvailable: Bool {
        availability.isAvailable
    }
}
