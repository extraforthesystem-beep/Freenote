import NoteCore
import Testing
@testable import SearchKit

private actor IndexOnlyRecognizer: HandwritingRecognizing {
    nonisolated let recognitionVersion = 1

    func text(for strokes: [StrokeRecord]) async -> String? {
        "101\nlol"
    }
}

@Test func recognizerBestReadingDefaultsToItsIndexText() async {
    let text = await IndexOnlyRecognizer().recognizedText(for: [])
    #expect(text == "101\nlol")
}

@Test func autoTitleUsesTheFirstSentence() {
    #expect(AutoTitle.suggestion(from: "the force of gravity pulls things down. Then it stops.")
        == "The force of gravity pulls things down")
    #expect(AutoTitle.suggestion(from: "Buy milk and eggs tomorrow")
        == "Buy milk and eggs tomorrow")
}

@Test func autoTitleCutsAtAWordBoundary() throws {
    let title = try #require(AutoTitle.suggestion(from: String(repeating: "word ", count: 20), maxLength: 20))
    #expect(title.count <= 20)
    #expect(title.hasSuffix("word"))
}

@Test func autoTitleRejectsUnusableText() {
    #expect(AutoTitle.suggestion(from: "") == nil)
    #expect(AutoTitle.suggestion(from: "   \n ") == nil)
    #expect(AutoTitle.suggestion(from: "Hello") == nil)
    #expect(AutoTitle.suggestion(from: "42 + 7 = 49") == nil)
    #expect(AutoTitle.suggestion(from: "• • •") == nil)
}

@Test func autoTitleFlattensLinesAndPunctuation() {
    #expect(AutoTitle.suggestion(from: "• Meeting notes\nTuesday with Sam")
        == "Meeting notes Tuesday with Sam")
}
