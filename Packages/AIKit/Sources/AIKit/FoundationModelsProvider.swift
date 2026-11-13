import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device language model behind the provider protocol.
///
/// The type is always constructible; every call re-checks the system model so
/// the app can move between available and unavailable without restarting.
public struct FoundationModelsProvider: AIProvider {
    /// The context size reported when the system model cannot be queried.
    public static let fallbackContextSize = 4_096

    /// Creates a provider; no setup is needed because the system model is shared.
    public init() {}

    /// A stable name for logs and diagnostics.
    public var identifier: String {
        "foundation-models"
    }

    /// The system model's current availability.
    public var availability: AIAvailability {
        #if canImport(FoundationModels)
        if #available(iOS 27.0, macOS 27.0, *) {
            return FoundationModelBridge.availability
        }
        #endif
        return .unsupportedOS
    }

    /// The system model's context window, or a conservative default.
    public var contextSize: Int {
        #if canImport(FoundationModels)
        if #available(iOS 27.0, macOS 27.0, *) {
            return FoundationModelBridge.contextSize
        }
        #endif
        return Self.fallbackContextSize
    }

    /// Languages the system model advertises, or an empty list.
    public var supportedLanguages: [Locale.Language] {
        #if canImport(FoundationModels)
        if #available(iOS 27.0, macOS 27.0, *) {
            return FoundationModelBridge.supportedLanguages
        }
        #endif
        return []
    }

    /// Answers a request with one session, so notes never share a transcript.
    public func respond(to request: AIRequest) async throws -> AIResponse {
        try Task.checkCancellation()
        #if canImport(FoundationModels)
        if #available(iOS 27.0, macOS 27.0, *) {
            let prompt = Self.makePrompt(for: request)
            do {
                let result = try await FoundationModelBridge.respond(
                    instructions: prompt.instructions,
                    prompt: prompt.prompt
                )
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return AIResponse(
                    text: text,
                    citations: Self.citations(for: request, output: text),
                    cards: Self.cards(for: request, text: text),
                    tokenUsage: result.tokenUsage,
                    didChangeText: Self.didChange(request: request, output: text)
                )
            } catch {
                throw AIErrorMapping.map(error)
            }
        }
        #endif
        throw AIError.unsupportedOS
    }

    /// Streams the system model's answer, yielding only the new suffix.
    public func stream(to request: AIRequest) -> AsyncThrowingStream<String, Error> {
        #if canImport(FoundationModels)
        if #available(iOS 27.0, macOS 27.0, *) {
            let prompt = Self.makePrompt(for: request)
            return Self.mapped(
                FoundationModelBridge.stream(instructions: prompt.instructions, prompt: prompt.prompt)
            )
        }
        #endif
        return AsyncThrowingStream { continuation in
            continuation.finish(throwing: AIError.unsupportedOS)
        }
    }

    // MARK: - Prompts

    private static func makePrompt(for request: AIRequest) -> (instructions: String, prompt: String) {
        switch request.kind {
        case .summarize(let text, let scope):
            return (
                "You summarize handwritten notes. Reply with at most three short sentences in the author's voice. Do not add facts.",
                "Summarize this \(scope.rawValue) as a short paragraph:\n\n\(text)"
            )
        case .rewrite(let text, let instruction):
            return (
                "Rewrite text exactly as instructed. Reply with only the rewritten text.",
                "Instruction: \(instruction)\n\nText:\n\(text)"
            )
        case .bullets(let text):
            return (
                "Turn notes into short bullet points. One idea per line, no preamble, no conclusion.",
                "Bullet-point these notes:\n\n\(text)"
            )
        case .grammar(let text):
            return (
                "Correct grammar, spelling and punctuation. Keep the author's voice and reply with only the corrected text.",
                text
            )
        case .tone(let text, let tone):
            return (
                "Rewrite in the requested tone. Reply with only the rewritten text.",
                "Tone: \(tone.rawValue)\n\nText:\n\(text)"
            )
        case .flashcards(let text, let maxCards):
            return (
                "Create study flashcards. Write one question and one answer per card as 'Q: ...' and 'A: ...' lines.",
                "Create at most \(max(0, maxCards)) flashcards from:\n\n\(text)"
            )
        case .ask(let question, let context):
            return (
                "Answer only from the supplied notes. If the answer is absent, reply exactly '\(DeterministicProvider.notFoundText)'. Quote the words you relied on.",
                "Notes:\n\(context)\n\nQuestion: \(question)"
            )
        case .math(let expression):
            return (
                "Solve the arithmetic exactly. Reply with the expression, an equals sign and the result.",
                expression
            )
        }
    }

    // MARK: - Result shaping

    private static func citations(for request: AIRequest, output: String) -> [AICitation] {
        switch request.kind {
        case .summarize, .bullets, .ask:
            guard let source = request.sourceText else { return [] }
            return CitationExtractor.citations(matching: output, in: source)
        default:
            return []
        }
    }

    private static func cards(for request: AIRequest, text: String) -> [AIFlashcard] {
        guard case .flashcards = request.kind else { return [] }
        return FlashcardParser.cards(in: text)
    }

    private static func didChange(request: AIRequest, output: String) -> Bool {
        guard let source = request.sourceText else { return true }
        return output != source
    }

    /// Applies typed error mapping to a provider stream without losing order.
    private static func mapped(
        _ upstream: AsyncThrowingStream<String, Error>
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await chunk in upstream {
                        try Task.checkCancellation()
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: AIErrorMapping.map(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - FoundationModels isolation

#if canImport(FoundationModels)
@available(iOS 27.0, macOS 27.0, *)
private enum FoundationModelBridge {
    static var availability: AIAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            return .unavailable(reason: map(reason))
        }
    }

    static var contextSize: Int {
        SystemLanguageModel.default.contextSize
    }

    static var supportedLanguages: [Locale.Language] {
        SystemLanguageModel.default.supportedLanguages
            .sorted { $0.minimalIdentifier < $1.minimalIdentifier }
    }

    /// Fails with a typed error before any model work when the model cannot answer.
    static func requireAvailable() throws {
        switch availability {
        case .available:
            return
        case .unavailable:
            throw AIError.unavailable
        case .unsupportedOS:
            throw AIError.unsupportedOS
        }
    }

    static func respond(instructions: String, prompt: String) async throws -> (text: String, tokenUsage: Int?) {
        try requireAvailable()
        let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
        let response = try await session.respond(to: prompt)
        return (response.content, response.usage.totalTokenCount)
    }

    static func stream(instructions: String, prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try requireAvailable()
                    let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
                    let stream = session.streamResponse(to: prompt)
                    var emitted = ""

                    for try await snapshot in stream {
                        try Task.checkCancellation()
                        let content = snapshot.content
                        guard content != emitted else { continue }
                        if content.hasPrefix(emitted) {
                            let delta = String(content.dropFirst(emitted.count))
                            if !delta.isEmpty {
                                continuation.yield(delta)
                            }
                        } else if !content.isEmpty {
                            // A non-cumulative snapshot: forward it as its own answer.
                            continuation.yield(content)
                        }
                        emitted = content
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: AIErrorMapping.map(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func map(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> AIUnavailableReason {
        switch reason {
        case .deviceNotEligible:
            return .deviceNotEligible
        case .appleIntelligenceNotEnabled:
            return .appleIntelligenceNotEnabled
        case .modelNotReady:
            return .modelNotReady
        @unknown default:
            return .unknown
        }
    }
}
#endif

/// Maps system model failures onto AIKit's typed errors.
private enum AIErrorMapping {
    static func map(_ error: Error) -> AIError {
        if let error = error as? AIError {
            return error
        }
        if error is CancellationError || Task.isCancelled {
            return .cancelled
        }
        return .providerFailure(error.localizedDescription)
    }
}
