import Foundation
import Testing
@testable import AIKit

private let note = """
The mitochondria is the powerhouse of the cell. It produces ATP through respiration. Cells store energy in glucose. Plants also use chloroplasts.
"""

private func makeRequest(_ kind: AIRequestKind) -> AIRequest {
    AIRequest(kind: kind)
}

@Test func summaryKeepsFirstThreeSentences() async throws {
    let provider = DeterministicProvider()
    let response = try await provider.respond(to: makeRequest(.summarize(text: note, scope: .page)))

    #expect(
        response.text
            == "The mitochondria is the powerhouse of the cell. It produces ATP through respiration. Cells store energy in glucose."
    )
    #expect(response.citations.count == 3)
    #expect(response.didChangeText)
    #expect(response.tokenUsage != nil)
}

@Test func summaryLengthIsConfigurable() async throws {
    let provider = DeterministicProvider(summarySentenceCount: 1)
    let response = try await provider.respond(to: makeRequest(.summarize(text: note, scope: .selection)))

    #expect(response.text == "The mitochondria is the powerhouse of the cell.")
    #expect(response.citations.count == 1)
}

@Test func bulletsSplitSentences() async throws {
    let provider = DeterministicProvider()
    let response = try await provider.respond(to: makeRequest(.bullets(text: note)))
    let lines = response.text.components(separatedBy: "\n")

    #expect(lines.count == 4)
    #expect(lines.allSatisfy { $0.hasPrefix("• ") })
    #expect(response.citations.count == 4)
}

@Test func flashcardsMakeClozeCards() async throws {
    let provider = DeterministicProvider()
    let response = try await provider.respond(to: makeRequest(.flashcards(text: note, maxCards: 2)))

    #expect(response.cards.count == 2)
    #expect(response.cards[0].question == "The mitochondria is ____")
    #expect(response.cards[0].answer == "the powerhouse of the cell.")
    #expect(response.cards[1].question.contains("What does the note say about"))
    #expect(response.cards[1].answer == "It produces ATP through respiration.")
    #expect(response.text.hasPrefix("Q: The mitochondria is ____\nA: the powerhouse of the cell."))
}

@Test func flashcardsRespectMaxCards() async throws {
    let provider = DeterministicProvider()

    let none = try await provider.respond(to: makeRequest(.flashcards(text: note, maxCards: 0)))
    #expect(none.cards.isEmpty)
    #expect(none.text.isEmpty)

    let one = try await provider.respond(to: makeRequest(.flashcards(text: note, maxCards: 1)))
    #expect(one.cards.count == 1)
}

@Test func askFindsRelevantSentence() async throws {
    let provider = DeterministicProvider()
    let response = try await provider.respond(
        to: makeRequest(.ask(question: "What produces ATP?", context: note))
    )

    #expect(response.text == "It produces ATP through respiration.")
    #expect(response.citations.count == 1)
    #expect(response.citations[0].text == "It produces ATP through respiration.")
}

@Test func askReportsNotFoundWithoutAMatch() async throws {
    let provider = DeterministicProvider()
    let response = try await provider.respond(
        to: makeRequest(.ask(question: "What is chlorophyll?", context: note))
    )

    #expect(response.text == DeterministicProvider.notFoundText)
    #expect(response.citations.isEmpty)
}

@Test func askReportsNotFoundForStopWordQuestions() async throws {
    let provider = DeterministicProvider()
    let response = try await provider.respond(
        to: makeRequest(.ask(question: "What is it?", context: note))
    )

    #expect(response.text == DeterministicProvider.notFoundText)
}

@Test func grammarReportsUnchanged() async throws {
    let provider = DeterministicProvider()
    let response = try await provider.respond(to: makeRequest(.grammar(text: "This are a sentence.")))

    #expect(response.text == "This are a sentence.")
    #expect(response.didChangeText == false)
    #expect(response.citations.isEmpty)
}

@Test func rewriteAndToneKeepTextWithoutAModel() async throws {
    let provider = DeterministicProvider()

    let rewrite = try await provider.respond(
        to: makeRequest(.rewrite(text: "Original words.", instruction: "Make it shorter."))
    )
    #expect(rewrite.text == "Original words.")
    #expect(rewrite.didChangeText == false)

    let tone = try await provider.respond(to: makeRequest(.tone(text: "Original words.", tone: .casual)))
    #expect(tone.text == "Original words.")
    #expect(tone.didChangeText == false)
}

@Test func mathEvaluatesArithmetic() async throws {
    let provider = DeterministicProvider()

    let simple = try await provider.respond(to: makeRequest(.math(expression: "2 + 3 * 4")))
    #expect(simple.text == "2 + 3 * 4 = 14")

    let grouped = try await provider.respond(to: makeRequest(.math(expression: "(2 + 3) * 4")))
    #expect(grouped.text == "(2 + 3) * 4 = 20")

    let decimal = try await provider.respond(to: makeRequest(.math(expression: "10 / 4")))
    #expect(decimal.text == "10 / 4 = 2.5")

    let power = try await provider.respond(to: makeRequest(.math(expression: "2 ^ 3 ^ 2")))
    #expect(power.text == "2 ^ 3 ^ 2 = 512")

    let percent = try await provider.respond(to: makeRequest(.math(expression: "50%")))
    #expect(percent.text == "50% = 0.5")
}

@Test func groupedExpressionTextKeepsTheInput() async throws {
    let provider = DeterministicProvider()
    let response = try await provider.respond(to: makeRequest(.math(expression: "(2 + 3) * 4")))

    // The prefix is the caller's own expression, not a re-rendered one.
    #expect(response.text.hasPrefix("(2 + 3) * 4 = "))
}

@Test func invalidMathIsExplained() async throws {
    let provider = DeterministicProvider()
    let response = try await provider.respond(to: makeRequest(.math(expression: "hello + world")))

    #expect(response.text.hasPrefix("Unable to evaluate"))
    #expect(response.didChangeText == false)
}

@Test func requestsAndResponsesRoundTripThroughCodable() throws {
    let request = AIRequest(kind: .ask(question: "What produces ATP?", context: note))
    let decodedRequest = try JSONDecoder().decode(
        AIRequest.self,
        from: JSONEncoder().encode(request)
    )
    #expect(decodedRequest == request)

    let response = AIResponse(
        text: "Answer.",
        citations: [AICitation(utf16Offset: 4, utf16Length: 7, text: "Answer.")],
        cards: [AIFlashcard(question: "Q", answer: "A")],
        tokenUsage: 12,
        didChangeText: false
    )
    let decodedResponse = try JSONDecoder().decode(
        AIResponse.self,
        from: JSONEncoder().encode(response)
    )
    #expect(decodedResponse == response)
}
