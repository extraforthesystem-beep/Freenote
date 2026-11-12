import Foundation
import StudyKit
import Testing

/// A fixed clock for every deterministic test.
let testNow = Date(timeIntervalSince1970: 1_700_000_000)

func makeCard(_ index: Int, now: Date = testNow) -> StudyCard {
    StudyCard(
        question: "Question \(index)",
        answer: "Answer \(index)",
        createdAt: now,
        updatedAt: now
    )
}

func makeSet(cardCount: Int, title: String = "Test Set", now: Date = testNow) -> StudySet {
    StudySet(
        title: title,
        cards: (0..<cardCount).map { makeCard($0, now: now) },
        createdAt: now,
        updatedAt: now
    )
}

func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("StudyKitTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Asserts that `body` throws exactly `expected`.
func expectError(_ expected: StudyKitError, _ body: () throws -> Void) {
    do {
        try body()
        Issue.record("Expected \(expected), but no error was thrown.")
    } catch let error as StudyKitError {
        #expect(error == expected)
    } catch {
        Issue.record("Expected \(expected), got \(error).")
    }
}

/// Asserts that an async `body` throws exactly `expected`.
func expectAsyncError(_ expected: StudyKitError, _ body: () async throws -> Void) async {
    do {
        try await body()
        Issue.record("Expected \(expected), but no error was thrown.")
    } catch let error as StudyKitError {
        #expect(error == expected)
    } catch {
        Issue.record("Expected \(expected), got \(error).")
    }
}
