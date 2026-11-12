import Foundation
import Testing
@testable import AIKit

@Test func sentenceRulesKeepAbbreviationsAndDecimalsTogether() async throws {
    let provider = DeterministicProvider(summarySentenceCount: 5)
    let text = "Dr. Chen measured 3.5 units. It was enough."

    let response = try await provider.respond(
        to: AIRequest(kind: .summarize(text: text, scope: .page))
    )

    #expect(response.text == text)
    #expect(response.citations.count == 2)
    #expect(response.citations[0].text == "Dr. Chen measured 3.5 units.")
}

@Test func sentenceRulesKeepInitialismsTogether() async throws {
    let provider = DeterministicProvider(summarySentenceCount: 5)
    let text = "The meeting is at 3 p.m. today. Bring notes."

    let response = try await provider.respond(
        to: AIRequest(kind: .summarize(text: text, scope: .page))
    )

    #expect(response.citations.count == 2)
    #expect(response.citations[0].text == "The meeting is at 3 p.m. today.")
}

@Test func availabilityExpressesUnsupportedOSAsAReason() {
    #expect(AIAvailability.available.reason == nil)
    #expect(AIAvailability.unsupportedOS.reason == .unsupportedOS)
    #expect(AIAvailability.unavailable(reason: .modelNotReady).reason == .modelNotReady)
    #expect(AIAvailability.unsupportedOS.isAvailable == false)
}

@Test func foundationModelsProviderReportsCapabilitiesSafely() async {
    let provider = FoundationModelsProvider()

    #expect(provider.identifier == "foundation-models")
    #expect(provider.contextSize > 0)
    #expect(provider.isAvailable == (provider.availability == .available))

    // Never call the model when it is unavailable; a direct provider call must
    // still fail with a typed error rather than crash.
    guard !provider.isAvailable else { return }
    do {
        _ = try await provider.respond(to: AIRequest(kind: .grammar(text: "text")))
        Issue.record("An unavailable model answered a request.")
    } catch let error as AIError {
        #expect(error == .unavailable || error == .unsupportedOS)
    } catch {
        Issue.record("Expected an AIError, got \(error).")
    }
}
