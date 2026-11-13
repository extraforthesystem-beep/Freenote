import Foundation

/// How much of a note a summary covers.
public enum AISummaryScope: String, Codable, Equatable, Sendable, CaseIterable {
    /// The selected text only.
    case selection
    /// The current page.
    case page
    /// Every page in the notebook.
    case notebook
}

/// The voice a tone request should use.
public enum AITone: String, Codable, Equatable, Sendable, CaseIterable {
    /// Neutral and businesslike.
    case professional
    /// Relaxed and conversational.
    case casual
    /// As short as the meaning allows.
    case concise
    /// Warm and approachable.
    case friendly
}

/// One study card produced by a flashcard request.
public struct AIFlashcard: Codable, Equatable, Hashable, Sendable {
    /// The prompt shown before the answer is revealed.
    public var question: String
    /// The answer revealed for `question`.
    public var answer: String

    /// Creates a card from a question and its answer.
    public init(question: String, answer: String) {
        self.question = question
        self.answer = answer
    }
}

/// A typed request the app can send to any provider.
public enum AIRequestKind: Codable, Equatable, Sendable {
    /// Condense `text` for `scope`.
    case summarize(text: String, scope: AISummaryScope)
    /// Rewrite `text` following a free-form instruction.
    case rewrite(text: String, instruction: String)
    /// Turn `text` into bullet points.
    case bullets(text: String)
    /// Correct grammar without changing meaning.
    case grammar(text: String)
    /// Rewrite `text` in `tone`.
    case tone(text: String, tone: AITone)
    /// Build up to `maxCards` question and answer pairs from `text`.
    case flashcards(text: String, maxCards: Int)
    /// Answer `question` using only `context`.
    case ask(question: String, context: String)
    /// Explain or evaluate an arithmetic expression.
    case math(expression: String)
}

/// A typed request, wrapping a kind so limits and logging have one input.
public struct AIRequest: Codable, Equatable, Sendable {
    /// The operation to perform.
    public var kind: AIRequestKind

    /// Wraps a request kind.
    public init(kind: AIRequestKind) {
        self.kind = kind
    }

    /// All text the request sends to a model; length limits apply to this.
    public var inputText: String {
        switch kind {
        case .summarize(let text, _),
             .rewrite(let text, _),
             .bullets(let text),
             .grammar(let text),
             .tone(let text, _),
             .flashcards(let text, _):
            return text
        case .ask(let question, let context):
            return question + "\n" + context
        case .math(let expression):
            return expression
        }
    }

    /// The note text the request is about, when there is one.
    public var sourceText: String? {
        switch kind {
        case .summarize(let text, _),
             .rewrite(let text, _),
             .bullets(let text),
             .grammar(let text),
             .tone(let text, _),
             .flashcards(let text, _):
            return text
        case .ask(_, let context):
            return context
        case .math:
            return nil
        }
    }
}

/// A source range cited by a generated answer, stored in UTF-16 units.
public struct AICitation: Codable, Equatable, Hashable, Sendable {
    /// Offset from the start of the source, in UTF-16 units.
    public var utf16Offset: Int
    /// Length of the cited text, in UTF-16 units.
    public var utf16Length: Int
    /// The cited source text, copied for display without re-reading the note.
    public var text: String

    /// Creates a citation from precomputed UTF-16 offsets and text.
    public init(utf16Offset: Int, utf16Length: Int, text: String) {
        self.utf16Offset = utf16Offset
        self.utf16Length = utf16Length
        self.text = text
    }

    /// Copies the UTF-16 offsets and text of `range` in `source`.
    public init(range: Range<String.Index>, in source: String) {
        self.utf16Offset = source[..<range.lowerBound].utf16.count
        self.utf16Length = source[range].utf16.count
        self.text = String(source[range])
    }

    /// The cited span as a UTF-16 range, ready for `NSString` or text views.
    public var utf16Range: Range<Int> {
        utf16Offset..<(utf16Offset + utf16Length)
    }
}

/// A provider's answer, with optional citations and usage.
public struct AIResponse: Codable, Equatable, Sendable {
    /// The answer text, ready to display.
    public var text: String
    /// Source sentences the answer relied on; empty when nothing is cited.
    public var citations: [AICitation]
    /// Structured cards for a flashcard request; empty for other requests.
    public var cards: [AIFlashcard]
    /// Rough token count for prompt plus answer, when known.
    public var tokenUsage: Int?
    /// False when an editing request deliberately returned the input unchanged.
    public var didChangeText: Bool

    /// Creates a response; citations, cards and usage default to empty or nil.
    public init(
        text: String,
        citations: [AICitation] = [],
        cards: [AIFlashcard] = [],
        tokenUsage: Int? = nil,
        didChangeText: Bool = true
    ) {
        self.text = text
        self.citations = citations
        self.cards = cards
        self.tokenUsage = tokenUsage
        self.didChangeText = didChangeText
    }
}

/// A failure the AI layer reports to the app.
public enum AIError: Error, Equatable, Sendable, LocalizedError {
    /// No provider can answer and no fallback is configured.
    case unavailable
    /// The running OS has no on-device language model and no fallback is configured.
    case unsupportedOS
    /// The request input was longer than the service allows.
    case tooLong(maximum: Int, actual: Int)
    /// The caller cancelled the request or stream.
    case cancelled
    /// The provider failed for a reason it could not classify.
    case providerFailure(String)

    /// A readable message the app can show without its own error table.
    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "On-device AI is not available right now."
        case .unsupportedOS:
            return "This operating system does not support on-device AI."
        case .tooLong(let maximum, let actual):
            return "The request is too long (\(actual) of \(maximum) allowed)."
        case .cancelled:
            return "The AI request was cancelled."
        case .providerFailure(let reason):
            return "The AI model failed: \(reason)"
        }
    }
}
