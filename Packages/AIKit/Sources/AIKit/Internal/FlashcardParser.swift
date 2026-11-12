import Foundation

/// Reads "Q: ..." and "A: ..." lines back into typed cards.
enum FlashcardParser {
    static func cards(in text: String) -> [AIFlashcard] {
        var cards: [AIFlashcard] = []
        var question: String?

        for rawLine in text.split(whereSeparator: { $0.isNewline }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Q:") || line.hasPrefix("Q：") {
                question = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("A:") || line.hasPrefix("A：") {
                let answer = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if let question, !question.isEmpty, !answer.isEmpty {
                    cards.append(AIFlashcard(question: question, answer: answer))
                }
                question = nil
            }
        }

        return cards
    }
}
