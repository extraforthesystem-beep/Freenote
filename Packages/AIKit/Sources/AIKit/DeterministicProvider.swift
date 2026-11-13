import Foundation

/// A pure-Swift provider used by tests and whenever the system model is absent.
///
/// Its answers are deterministic: the same request always produces the same
/// text, citations and card order, and it never touches the network.
public struct DeterministicProvider: AIProvider {
    /// The answer returned when a question matches nothing in its context.
    public static let notFoundText = "Not found in the note."

    /// How many leading sentences a summary keeps.
    public let summarySentenceCount: Int
    /// The context size reported to callers.
    public let contextSize: Int

    /// Creates a provider with a summary length and reported context size.
    public init(summarySentenceCount: Int = 3, contextSize: Int = 8_192) {
        self.summarySentenceCount = max(1, summarySentenceCount)
        self.contextSize = max(1, contextSize)
    }

    /// A stable name for logs and diagnostics.
    public var identifier: String {
        "deterministic"
    }

    /// The fallback is always ready.
    public var availability: AIAvailability {
        .available
    }

    /// Sentence rules are English-oriented; other text still passes through.
    public var supportedLanguages: [Locale.Language] {
        [Locale.Language(languageCode: "en")]
    }

    /// Answers immediately with the deterministic result.
    public func respond(to request: AIRequest) async throws -> AIResponse {
        try Task.checkCancellation()
        return response(for: request)
    }

    /// Streams the answer sentence by sentence, preserving its exact text.
    public func stream(to request: AIRequest) -> AsyncThrowingStream<String, Error> {
        let response = response(for: request)
        let chunks = Self.chunks(of: response.text)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try Task.checkCancellation()
                    for chunk in chunks {
                        try Task.checkCancellation()
                        continuation.yield(chunk)
                        await Task.yield()
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: AIError.cancelled)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Answers

    private func response(for request: AIRequest) -> AIResponse {
        switch request.kind {
        case .summarize(let text, _):
            return summarize(text)
        case .rewrite(let text, _):
            return unchanged(text)
        case .bullets(let text):
            return bullets(text)
        case .grammar(let text):
            return grammar(text)
        case .tone(let text, _):
            return unchanged(text)
        case .flashcards(let text, let maxCards):
            return flashcards(text, maxCards: maxCards)
        case .ask(let question, let context):
            return ask(question: question, context: context)
        case .math(let expression):
            return math(expression)
        }
    }

    private func summarize(_ text: String) -> AIResponse {
        let sentences = SentenceSplitter.sentences(in: text)
        let chosen = Array(sentences.prefix(summarySentenceCount))
        let summary = chosen.joined(separator: " ")
        return AIResponse(
            text: summary,
            citations: CitationExtractor.citations(forSentences: chosen, in: text),
            tokenUsage: TokenEstimator.estimate(prompt: text, output: summary),
            didChangeText: summary != text
        )
    }

    private func bullets(_ text: String) -> AIResponse {
        let sentences = SentenceSplitter.sentences(in: text)
        let output = sentences.map { "• " + $0 }.joined(separator: "\n")
        return AIResponse(
            text: output,
            citations: CitationExtractor.citations(forSentences: sentences, in: text),
            tokenUsage: TokenEstimator.estimate(prompt: text, output: output),
            didChangeText: output != text
        )
    }

    /// Grammar is a no-op, so the text comes back byte-for-byte unchanged.
    private func grammar(_ text: String) -> AIResponse {
        AIResponse(text: text, didChangeText: false)
    }

    /// Rewriting and tone changes need a language model, so the text is kept.
    private func unchanged(_ text: String) -> AIResponse {
        AIResponse(text: text, didChangeText: false)
    }

    private func flashcards(_ text: String, maxCards: Int) -> AIResponse {
        let limit = max(0, maxCards)
        guard limit > 0 else {
            return AIResponse(text: "", didChangeText: false)
        }

        let sentences = SentenceSplitter.sentences(in: text)
        let cards = sentences.prefix(limit).map(Self.card(for:))
        let output = cards
            .map { "Q: \($0.question)\nA: \($0.answer)" }
            .joined(separator: "\n\n")
        return AIResponse(
            text: output,
            cards: cards,
            tokenUsage: TokenEstimator.estimate(prompt: text, output: output)
        )
    }

    private func ask(question: String, context: String) -> AIResponse {
        let terms = Self.searchTerms(in: question)
        guard !terms.isEmpty else {
            return notFound(question: question)
        }

        let sentences = SentenceSplitter.sentences(in: context)
        var matches: [Match] = []
        for (index, sentence) in sentences.enumerated() {
            let haystack = sentence.lowercased()
            let score = terms.reduce(0) { count, term in
                count + (haystack.contains(term) ? 1 : 0)
            }
            if score > 0 {
                matches.append(Match(index: index, sentence: sentence, score: score))
            }
        }
        guard !matches.isEmpty else {
            return notFound(question: question)
        }

        let best = matches
            .sorted { left, right in
                left.score == right.score ? left.index < right.index : left.score > right.score
            }
            .prefix(Self.askSentenceLimit)
            .sorted { $0.index < $1.index }
        let answer = best.map(\.sentence).joined(separator: " ")
        return AIResponse(
            text: answer,
            citations: CitationExtractor.citations(forSentences: best.map(\.sentence), in: context),
            tokenUsage: TokenEstimator.estimate(prompt: question + context, output: answer)
        )
    }

    private func math(_ expression: String) -> AIResponse {
        guard let value = ArithmeticEvaluator.evaluate(expression) else {
            return AIResponse(
                text: "Unable to evaluate \"\(expression)\" as arithmetic.",
                didChangeText: false
            )
        }
        let text = "\(expression.trimmingCharacters(in: .whitespacesAndNewlines)) = \(ArithmeticEvaluator.format(value))"
        return AIResponse(
            text: text,
            tokenUsage: TokenEstimator.estimate(prompt: expression, output: text)
        )
    }

    private func notFound(question: String) -> AIResponse {
        AIResponse(
            text: Self.notFoundText,
            tokenUsage: TokenEstimator.estimate(prompt: question, output: Self.notFoundText)
        )
    }

    // MARK: - Flashcards

    /// Builds a cloze card from a sentence, falling back to a recall card.
    private static func card(for sentence: String) -> AIFlashcard {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let copulas = [" is ", " are ", " was ", " were ", " means ", " refers to "]

        for copula in copulas {
            guard let range = trimmed.range(of: copula, options: [.caseInsensitive]) else { continue }
            let subject = trimmed[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let predicate = trimmed[range.upperBound...].trimmingCharacters(in: .whitespaces)
            let word = trimmed[range].trimmingCharacters(in: .whitespaces)
            guard !subject.isEmpty, !predicate.isEmpty, !word.isEmpty else { continue }
            return AIFlashcard(question: "\(subject) \(word) ____", answer: predicate)
        }

        let keywords = trimmed
            .split(separator: " ")
            .prefix(6)
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
        return AIFlashcard(
            question: "What does the note say about “\(keywords)”?",
            answer: trimmed
        )
    }

    // MARK: - Matching

    private struct Match {
        let index: Int
        let sentence: String
        let score: Int
    }

    private static let askSentenceLimit = 3

    private static let stopWords: Set<String> = [
        "a", "about", "an", "and", "are", "as", "at", "be", "but", "by",
        "can", "could", "did", "do", "does", "for", "from", "had", "has",
        "have", "how", "i", "in", "into", "is", "it", "its", "me", "my",
        "note", "notes", "of", "on", "or", "our", "should", "that", "the",
        "their", "them", "then", "there", "these", "they", "this", "to",
        "us", "was", "we", "were", "what", "when", "where", "which", "who",
        "why", "will", "with", "would", "you", "your",
    ]

    private static func searchTerms(in question: String) -> [String] {
        let words = question.lowercased().split { !$0.isLetter && !$0.isNumber }
        return Set(words.map(String.init))
            .filter { $0.count > 1 && !stopWords.contains($0) }
            .sorted()
    }

    // MARK: - Streaming

    /// Splits `text` at sentence boundaries without losing a character.
    ///
    /// Each trailing separator stays with the sentence before it, so joining
    /// the chunks reproduces `text` exactly.
    private static func chunks(of text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        let ranges = SentenceSplitter.ranges(in: text)
        guard ranges.count > 1 else { return [text] }

        var boundaries: [String.Index] = [text.startIndex]
        boundaries.append(contentsOf: ranges.dropFirst().map(\.lowerBound))
        boundaries.append(text.endIndex)

        var chunks: [String] = []
        for index in 0..<(boundaries.count - 1) {
            let chunk = String(text[boundaries[index]..<boundaries[index + 1]])
            if !chunk.isEmpty {
                chunks.append(chunk)
            }
        }
        return chunks
    }
}
