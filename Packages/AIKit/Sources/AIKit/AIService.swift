import Foundation

/// Chooses a provider, enforces input limits and reports typed failures.
public actor AIService {
    /// The largest request, counted in UTF-16 units of `AIRequest.inputText`.
    public let maximumInputLength: Int

    private let onDevice: (any AIProvider)?
    private let fallback: (any AIProvider)?

    /// Creates a service with an optional on-device provider and fallback.
    ///
    /// Passing `nil` for both providers makes every request fail with
    /// `AIError.unavailable`, which is useful for tests and explicit opt-outs.
    public init(
        onDevice: (any AIProvider)? = FoundationModelsProvider(),
        fallback: (any AIProvider)? = DeterministicProvider(),
        maximumInputLength: Int = 12_000
    ) {
        self.onDevice = onDevice
        self.fallback = fallback
        self.maximumInputLength = max(0, maximumInputLength)
    }

    /// The on-device model's availability, or the fallback's when none is set.
    public nonisolated var availability: AIAvailability {
        onDevice?.availability ?? fallback?.availability ?? .unsupportedOS
    }

    /// Answers a request through the best available provider.
    ///
    /// - Throws: `AIError.tooLong` before any provider call, `AIError.unavailable`
    ///   or `AIError.unsupportedOS` when no provider can answer, and
    ///   `AIError.cancelled` when the calling task is cancelled.
    public func respond(to request: AIRequest) async throws -> AIResponse {
        do {
            try validate(request)
            let provider = try selectedProvider()
            try Task.checkCancellation()
            let response = try await provider.respond(to: request)
            try Task.checkCancellation()
            return response
        } catch {
            throw Self.mappedError(error)
        }
    }

    /// Streams a request through the best available provider.
    ///
    /// A validation or availability failure finishes the stream with the same
    /// error `respond(to:)` would throw.
    public func stream(to request: AIRequest) -> AsyncThrowingStream<String, Error> {
        let provider: any AIProvider
        do {
            try validate(request)
            provider = try selectedProvider()
        } catch {
            let mapped = Self.mappedError(error)
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: mapped)
            }
        }

        let upstream = provider.stream(to: request)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await chunk in upstream {
                        try Task.checkCancellation()
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.mappedError(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Selection

    private func validate(_ request: AIRequest) throws {
        let length = request.inputText.utf16.count
        guard length <= maximumInputLength else {
            throw AIError.tooLong(maximum: maximumInputLength, actual: length)
        }
    }

    private func selectedProvider() throws -> any AIProvider {
        if let onDevice, onDevice.isAvailable {
            return onDevice
        }
        if let fallback {
            return fallback
        }
        if let onDevice, case .unsupportedOS = onDevice.availability {
            throw AIError.unsupportedOS
        }
        throw AIError.unavailable
    }

    private static func mappedError(_ error: Error) -> AIError {
        if let error = error as? AIError {
            return error
        }
        if error is CancellationError || Task.isCancelled {
            return .cancelled
        }
        return .providerFailure(error.localizedDescription)
    }
}
