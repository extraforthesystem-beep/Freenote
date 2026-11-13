import Foundation
import Testing
@testable import AIKit

private let note = "The mitochondria is the powerhouse of the cell. It produces ATP through respiration. Cells store energy in glucose."

private struct StubProvider: AIProvider {
    let availability: AIAvailability
    let reply: String

    var identifier: String { "stub" }
    var contextSize: Int { 4_096 }
    var supportedLanguages: [Locale.Language] { [] }

    func respond(to request: AIRequest) async throws -> AIResponse {
        AIResponse(text: reply)
    }

    func stream(to request: AIRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(reply)
            continuation.finish()
        }
    }
}

private struct HangingProvider: AIProvider {
    var availability: AIAvailability { .available }
    var identifier: String { "hanging" }
    var contextSize: Int { 4_096 }
    var supportedLanguages: [Locale.Language] { [] }

    func respond(to request: AIRequest) async throws -> AIResponse {
        try await Task.sleep(for: .seconds(60))
        return AIResponse(text: "late")
    }

    func stream(to request: AIRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("late")
            continuation.finish()
        }
    }
}

private func expectAIError(
    _ expected: AIError,
    _ operation: () async throws -> Void
) async {
    do {
        try await operation()
        Issue.record("Expected \(expected) but no error was thrown.")
    } catch let error as AIError {
        #expect(error == expected)
    } catch {
        Issue.record("Expected \(expected) but got \(error).")
    }
}

private func firstError(
    in stream: AsyncThrowingStream<String, Error>
) async -> AIError? {
    do {
        for try await _ in stream {}
        return nil
    } catch {
        return error as? AIError
    }
}

@Test func servicePrefersTheAvailableOnDeviceProvider() async throws {
    let service = AIService(
        onDevice: StubProvider(availability: .available, reply: "model answer"),
        fallback: DeterministicProvider()
    )

    let response = try await service.respond(to: AIRequest(kind: .bullets(text: note)))
    #expect(response.text == "model answer")
}

@Test func serviceFallsBackWhenTheModelIsUnavailable() async throws {
    let service = AIService(
        onDevice: StubProvider(
            availability: .unavailable(reason: .appleIntelligenceNotEnabled),
            reply: "model answer"
        ),
        fallback: DeterministicProvider()
    )

    let response = try await service.respond(
        to: AIRequest(kind: .summarize(text: note, scope: .page))
    )
    #expect(response.text == "The mitochondria is the powerhouse of the cell. It produces ATP through respiration. Cells store energy in glucose.")
    #expect(response.citations.count == 3)
}

@Test func serviceReportsUnavailableWithoutAFallback() async {
    let service = AIService(
        onDevice: StubProvider(availability: .unavailable(reason: .modelNotReady), reply: "never"),
        fallback: nil
    )

    await expectAIError(.unavailable) {
        _ = try await service.respond(to: AIRequest(kind: .grammar(text: "text")))
    }
}

@Test func serviceReportsUnsupportedOSWithoutAFallback() async {
    let service = AIService(
        onDevice: StubProvider(availability: .unsupportedOS, reply: "never"),
        fallback: nil
    )

    await expectAIError(.unsupportedOS) {
        _ = try await service.respond(to: AIRequest(kind: .grammar(text: "text")))
    }
}

@Test func serviceReportsUnavailableWhenNoProviderIsConfigured() async {
    let service = AIService(onDevice: nil, fallback: nil)

    await expectAIError(.unavailable) {
        _ = try await service.respond(to: AIRequest(kind: .grammar(text: "text")))
    }
}

@Test func serviceRejectsInputsOverTheLimit() async {
    let service = AIService(
        onDevice: nil,
        fallback: DeterministicProvider(),
        maximumInputLength: 20
    )
    let text = String(repeating: "a", count: 21)

    await expectAIError(.tooLong(maximum: 20, actual: 21)) {
        _ = try await service.respond(to: AIRequest(kind: .summarize(text: text, scope: .page)))
    }
}

@Test func lengthLimitCountsUTF16Units() async {
    let service = AIService(
        onDevice: nil,
        fallback: DeterministicProvider(),
        maximumInputLength: 1
    )

    await expectAIError(.tooLong(maximum: 1, actual: 2)) {
        _ = try await service.respond(to: AIRequest(kind: .grammar(text: "😀")))
    }
}

@Test func serviceAcceptsInputExactlyAtTheLimit() async throws {
    let service = AIService(
        onDevice: nil,
        fallback: DeterministicProvider(),
        maximumInputLength: 5
    )

    let response = try await service.respond(to: AIRequest(kind: .grammar(text: "12345")))
    #expect(response.text == "12345")
}

@Test func serviceStreamReportsTooLongInput() async {
    let service = AIService(
        onDevice: nil,
        fallback: DeterministicProvider(),
        maximumInputLength: 3
    )
    let stream = await service.stream(to: AIRequest(kind: .grammar(text: "1234")))
    let error = await firstError(in: stream)

    #expect(error == .tooLong(maximum: 3, actual: 4))
}

@Test func serviceStreamReportsUnavailable() async {
    let service = AIService(
        onDevice: StubProvider(availability: .unavailable(reason: .deviceNotEligible), reply: "never"),
        fallback: nil
    )
    let stream = await service.stream(to: AIRequest(kind: .grammar(text: "text")))
    let error = await firstError(in: stream)

    #expect(error == .unavailable)
}

@Test func serviceMapsCancellationToTypedError() async {
    let service = AIService(onDevice: HangingProvider(), fallback: nil)
    let task = Task {
        try await service.respond(to: AIRequest(kind: .summarize(text: note, scope: .page)))
    }

    task.cancel()
    let result = await task.result

    switch result {
    case .success:
        Issue.record("Expected cancellation.")
    case .failure(let error):
        #expect((error as? AIError) == .cancelled)
    }
}

@Test func availabilityReflectsTheOnDeviceProvider() {
    let service = AIService(
        onDevice: StubProvider(availability: .unavailable(reason: .modelNotReady), reply: "never"),
        fallback: DeterministicProvider()
    )

    #expect(service.availability == .unavailable(reason: .modelNotReady))
}
