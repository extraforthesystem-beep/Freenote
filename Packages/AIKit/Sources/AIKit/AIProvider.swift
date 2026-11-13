import Foundation

/// A source of AI answers, either Apple's model or a local fallback.
public protocol AIProvider: AICapabilityReporting {
    /// A stable name for logs and diagnostics.
    var identifier: String { get }

    /// Answers a request in one piece.
    func respond(to request: AIRequest) async throws -> AIResponse

    /// Streams the answer as text fragments in order.
    ///
    /// Concatenating every fragment equals the `respond(to:)` text for
    /// providers that can produce their answer deterministically. Iteration
    /// ends with an `AIError.cancelled` error when the consuming task is
    /// cancelled.
    func stream(to request: AIRequest) -> AsyncThrowingStream<String, Error>
}
