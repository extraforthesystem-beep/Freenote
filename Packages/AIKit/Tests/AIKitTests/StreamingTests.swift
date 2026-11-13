import Foundation
import Testing
@testable import AIKit

private let note = "The mitochondria is the powerhouse of the cell. It produces ATP through respiration. Cells store energy in glucose. Plants also use chloroplasts."

private struct ChunkingProvider: AIProvider {
    let availability: AIAvailability
    let chunks: [String]

    init(availability: AIAvailability = .available, chunks: [String]) {
        self.availability = availability
        self.chunks = chunks
    }

    var identifier: String { "chunking" }
    var contextSize: Int { 4_096 }
    var supportedLanguages: [Locale.Language] { [] }

    func respond(to request: AIRequest) async throws -> AIResponse {
        AIResponse(text: chunks.joined())
    }

    func stream(to request: AIRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }
}

private func collect(_ stream: AsyncThrowingStream<String, Error>) async throws -> [String] {
    var chunks: [String] = []
    for try await chunk in stream {
        chunks.append(chunk)
    }
    return chunks
}

@Test func summaryStreamKeepsSentenceOrder() async throws {
    let provider = DeterministicProvider()
    let request = AIRequest(kind: .summarize(text: note, scope: .page))
    let response = try await provider.respond(to: request)
    let chunks = try await collect(provider.stream(to: request))

    #expect(chunks.count == 3)
    #expect(chunks.joined() == response.text)
    #expect(chunks[0] == "The mitochondria is the powerhouse of the cell. ")
    #expect(chunks[1] == "It produces ATP through respiration. ")
    #expect(chunks[2] == "Cells store energy in glucose.")
}

@Test func bulletStreamIsOneChunkPerLine() async throws {
    let provider = DeterministicProvider()
    let request = AIRequest(kind: .bullets(text: note))
    let response = try await provider.respond(to: request)
    let chunks = try await collect(provider.stream(to: request))

    #expect(chunks.count == 4)
    #expect(chunks.joined() == response.text)
    #expect(chunks.dropLast().allSatisfy { $0.hasSuffix("\n") })
    #expect(chunks.last?.hasSuffix("\n") == false)
}

@Test func flashcardStreamKeepsCardOrder() async throws {
    let provider = DeterministicProvider()
    let request = AIRequest(kind: .flashcards(text: note, maxCards: 2))
    let response = try await provider.respond(to: request)
    let chunks = try await collect(provider.stream(to: request))

    #expect(chunks.count == 4)
    #expect(chunks.joined() == response.text)
    #expect(chunks[0].hasPrefix("Q: The mitochondria is ____"))
    #expect(chunks[2].hasPrefix("Q: What does the note say about"))
}

@Test func singlePieceStreamsYieldTheWholeText() async throws {
    let provider = DeterministicProvider()
    let request = AIRequest(kind: .grammar(text: "This are unchanged."))
    let chunks = try await collect(provider.stream(to: request))

    #expect(chunks == ["This are unchanged."])
}

@Test func emptyTextStreamsNothing() async throws {
    let provider = DeterministicProvider()
    let chunks = try await collect(
        provider.stream(to: AIRequest(kind: .summarize(text: "", scope: .page)))
    )

    #expect(chunks.isEmpty)
}

@Test func serviceKeepsProviderChunkOrder() async throws {
    let service = AIService(
        onDevice: ChunkingProvider(chunks: ["one ", "two ", "three"]),
        fallback: nil
    )
    let chunks = try await collect(service.stream(to: AIRequest(kind: .grammar(text: "text"))))

    #expect(chunks == ["one ", "two ", "three"])
}

@Test func serviceStreamsTheDeterministicFallback() async throws {
    let service = AIService(
        onDevice: ChunkingProvider(
            availability: .unavailable(reason: .modelNotReady),
            chunks: ["never"]
        ),
        fallback: DeterministicProvider()
    )
    let request = AIRequest(kind: .summarize(text: note, scope: .page))
    let full = try await service.respond(to: request)
    let chunks = try await collect(service.stream(to: request))

    #expect(full.citations.count == 3)
    #expect(chunks.count == 3)
    #expect(chunks.joined() == full.text)
}
