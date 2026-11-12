import Foundation
import Testing
@testable import AIKit

private let note = """
The mitochondria is the powerhouse of the cell. It produces ATP through respiration. Cells store energy in glucose. Plants also use chloroplasts.
"""

@Test func citationKeepsUTF16Offsets() throws {
    let source = "😀 Café résumé here! Second sentence."
    let citations = CitationExtractor.citations(matching: "Café résumé here!", in: source)

    #expect(citations.count == 1)
    let citation = try #require(citations.first)
    #expect(citation.utf16Offset == 3)
    #expect(citation.utf16Length == "Café résumé here!".utf16.count)

    let slice = Array(source.utf16)[citation.utf16Range]
    #expect(String(decoding: slice, as: UTF16.self) == "Café résumé here!")
}

@Test func citationMatchingIgnoresCaseAndDiacritics() throws {
    let source = "Café résumé here! Second sentence."
    let citations = CitationExtractor.citations(matching: "cafe resume here!", in: source)

    let citation = try #require(citations.first)
    #expect(citation.text == "Café résumé here!")
    #expect(citation.utf16Offset == 0)
}

@Test func unmatchedOutputReturnsNoCitations() {
    let source = "The mitochondria is the powerhouse of the cell."
    #expect(CitationExtractor.citations(matching: "Completely different.", in: source).isEmpty)
    #expect(CitationExtractor.citations(matching: "", in: source).isEmpty)
    #expect(CitationExtractor.citations(matching: "anything", in: "").isEmpty)
}

@Test func bulletPrefixesAreIgnoredWhenMatching() {
    let source = "First point. Second point."
    let citations = CitationExtractor.citations(matching: "• First point.\n• Second point.", in: source)

    #expect(citations.count == 2)
    #expect(citations.map(\.text) == ["First point.", "Second point."])
    #expect(citations[0].utf16Offset < citations[1].utf16Offset)
}

@Test func summaryCitationsPointAtTheSourceSentences() async throws {
    let provider = DeterministicProvider()
    let response = try await provider.respond(
        to: AIRequest(kind: .summarize(text: note, scope: .page))
    )

    #expect(response.citations.map(\.text) == [
        "The mitochondria is the powerhouse of the cell.",
        "It produces ATP through respiration.",
        "Cells store energy in glucose.",
    ])

    for citation in response.citations {
        let slice = Array(note.utf16)[citation.utf16Range]
        #expect(String(decoding: slice, as: UTF16.self) == citation.text)
    }
}

@Test func answerCitationsPointAtTheMatchingSentence() async throws {
    let provider = DeterministicProvider()
    let response = try await provider.respond(
        to: AIRequest(kind: .ask(question: "What do cells store?", context: note))
    )

    let citation = try #require(response.citations.first)
    #expect(citation.text == "Cells store energy in glucose.")
    #expect(String(decoding: Array(note.utf16)[citation.utf16Range], as: UTF16.self) == citation.text)
}

@Test func citationFromRangeUsesSourceOffsets() throws {
    let source = "😀 Intro. Second sentence."
    let range = try #require(source.range(of: "Second sentence."))
    let citation = AICitation(range: range, in: source)

    #expect(citation.text == "Second sentence.")
    #expect(citation.utf16Offset == source[..<range.lowerBound].utf16.count)
    #expect(citation.utf16Length == "Second sentence.".utf16.count)
    #expect(citation.utf16Range == citation.utf16Offset..<(citation.utf16Offset + citation.utf16Length))
}

@Test func citationForSubstringReturnsNilWhenAbsent() {
    #expect(CitationExtractor.citation(for: "Second sentence.", in: "😀 Intro. Second sentence.") != nil)
    #expect(CitationExtractor.citation(for: "Missing.", in: "😀 Intro. Second sentence.") == nil)
}
