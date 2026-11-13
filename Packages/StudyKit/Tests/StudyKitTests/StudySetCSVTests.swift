import Foundation
import StudyKit
import Testing

@Suite("Study set CSV")
struct StudySetCSVTests {
    @Test func exportThenImportPreservesCommasQuotesAndNewlines() throws {
        let cards = [
            StudyCard(question: "Plain", answer: "4", createdAt: testNow, updatedAt: testNow),
            StudyCard(question: "Comma, here", answer: "a,b,c", createdAt: testNow, updatedAt: testNow),
            StudyCard(
                question: "Quote \"inside\"",
                answer: "She said \"hello\"",
                createdAt: testNow,
                updatedAt: testNow
            ),
            StudyCard(
                question: "Multi\nline",
                answer: "first\r\nsecond\nthird",
                createdAt: testNow,
                updatedAt: testNow
            ),
            StudyCard(question: "Only a line break", answer: "\r\n", createdAt: testNow, updatedAt: testNow),
            StudyCard(question: " Empty answer ", answer: "", createdAt: testNow, updatedAt: testNow),
        ]
        let set = StudySet(
            title: "Tricky",
            cards: cards,
            createdAt: testNow,
            updatedAt: testNow,
            colorTag: "blue"
        )

        let text = StudySetCSV.export(set)
        #expect(text.hasPrefix("question,answer\r\n"))
        #expect(text.contains("\"Comma, here\""))

        let imported = try StudySetCSV.importSet(from: text, title: "Tricky", now: testNow)

        #expect(imported.title == "Tricky")
        #expect(imported.createdAt == testNow)
        #expect(imported.updatedAt == testNow)
        #expect(imported.colorTag == "")
        #expect(imported.cards.map(\.question) == cards.map(\.question))
        #expect(imported.cards.map(\.answer) == cards.map(\.answer))
        #expect(imported.cards.allSatisfy { $0.createdAt == testNow && $0.updatedAt == testNow })
    }

    @Test func exportOfAnEmptySetIsJustTheHeader() {
        let set = StudySet(title: "Empty", cards: [], createdAt: testNow, updatedAt: testNow)
        #expect(StudySetCSV.export(set) == "question,answer\r\n")
    }

    @Test func importAcceptsLFCRAndCRLFLineEndings() throws {
        let text = "question,answer\nalpha,one\rbravo,\"two, too\"\ncharlie,\"three\r\nlines\"\n"
        let set = try StudySetCSV.importSet(from: text, title: "Mixed", now: testNow)

        #expect(set.cards.map(\.question) == ["alpha", "bravo", "charlie"])
        #expect(set.cards.map(\.answer) == ["one", "two, too", "three\r\nlines"])
    }

    @Test func importUnescapesDoubledQuotes() throws {
        let text = "question,answer\n\"He said \"\"hi\"\"\",\"a \"\"quote\"\"\"\n"
        let set = try StudySetCSV.importSet(from: text, title: "Quotes", now: testNow)

        #expect(set.cards.count == 1)
        #expect(set.cards[0].question == "He said \"hi\"")
        #expect(set.cards[0].answer == "a \"quote\"")
    }

    @Test func importAcceptsABOMQuotedHeaderAndBlankLines() throws {
        let text = "\u{FEFF}\"question\",\"answer\"\n\nq1,a1\n\nq2,a2\n\n"
        let set = try StudySetCSV.importSet(from: text, title: "Friendly", now: testNow)

        #expect(set.cards.map(\.question) == ["q1", "q2"])
    }

    @Test func headerIsMatchedCaseInsensitivelyAndCanBeTheOnlyRow() throws {
        let set = try StudySetCSV.importSet(
            from: " Question , ANSWER \n",
            title: "Header only",
            now: testNow
        )

        #expect(set.cards.isEmpty)
    }

    @Test func importedCardsGetFreshUniqueIdentifiers() throws {
        let set = try StudySetCSV.importSet(
            from: "question,answer\nq1,a1\nq2,a2\n",
            title: "Ids",
            now: testNow
        )

        #expect(Set(set.cards.map(\.id)).count == 2)
        #expect(set.cards[0].id != set.cards[1].id)
    }

    @Test func emptyDocumentThrowsTypedError() {
        expectError(.emptyCSV) {
            _ = try StudySetCSV.importSet(from: "", title: "Empty")
        }
        expectError(.emptyCSV) {
            _ = try StudySetCSV.importSet(from: "\n\r\n", title: "Blank")
        }
    }

    @Test func wrongHeaderThrowsTypedError() {
        expectError(.invalidCSVHeader(found: ["name", "answer"])) {
            _ = try StudySetCSV.importSet(from: "name,answer\nq,a\n", title: "Bad")
        }
        expectError(.invalidCSVHeader(found: ["question", "answer", "notes"])) {
            _ = try StudySetCSV.importSet(from: "question,answer,notes\nq,a,n\n", title: "Wide")
        }
    }

    @Test func wrongFieldCountThrowsTypedError() {
        expectError(.wrongFieldCount(row: 2, expected: 2, found: 1)) {
            _ = try StudySetCSV.importSet(from: "question,answer\nonly one\n", title: "Narrow")
        }
        expectError(.wrongFieldCount(row: 2, expected: 2, found: 3)) {
            _ = try StudySetCSV.importSet(from: "question,answer\nq,a,extra\n", title: "Wide")
        }
    }

    @Test func unterminatedQuoteThrowsTypedError() {
        expectError(.unterminatedQuotedField(row: 2)) {
            _ = try StudySetCSV.importSet(
                from: "question,answer\n\"never closed,a\n",
                title: "Broken"
            )
        }
    }

    @Test func quoteInsideUnquotedFieldThrowsTypedError() {
        expectError(.unexpectedQuote(row: 2, column: 2)) {
            _ = try StudySetCSV.importSet(from: "question,answer\nq\"uote,a\n", title: "Broken")
        }
    }

    @Test func characterAfterClosingQuoteThrowsTypedError() {
        expectError(.unexpectedCharacterAfterQuote(row: 2, column: 4)) {
            _ = try StudySetCSV.importSet(from: "question,answer\n\"q\"x,a\n", title: "Broken")
        }
        expectError(.unexpectedCharacterAfterQuote(row: 2, column: 4)) {
            _ = try StudySetCSV.importSet(from: "question,answer\n\"q\" ,a\n", title: "Broken")
        }
    }

    @Test func errorRowsUsePhysicalLineNumbers() {
        expectError(.wrongFieldCount(row: 4, expected: 2, found: 1)) {
            _ = try StudySetCSV.importSet(
                from: "question,answer\n\nq1,a1\nonly one\n",
                title: "Lines"
            )
        }
    }

    @Test func importAcceptsFrontBackAndTermDefinitionHeaders() throws {
        let front = try StudySetCSV.importSet(
            from: " Front , BACK \nq1,a1\n",
            title: "Front",
            now: testNow
        )
        #expect(front.cards.map(\.question) == ["q1"])
        #expect(front.cards.map(\.answer) == ["a1"])

        let term = try StudySetCSV.importSet(
            from: "term,definition\nmitosis,cell division\n",
            title: "Term",
            now: testNow
        )
        #expect(term.cards.map(\.question) == ["mitosis"])
        #expect(term.cards.map(\.answer) == ["cell division"])
    }

    @Test func importRejectsUnknownOrSwappedHeaders() {
        expectError(.invalidCSVHeader(found: ["prompt", "answer"])) {
            _ = try StudySetCSV.importSet(from: "prompt,answer\nq,a\n", title: "Unknown")
        }
        expectError(.invalidCSVHeader(found: ["answer", "question"])) {
            _ = try StudySetCSV.importSet(from: "answer,question\nq,a\n", title: "Swapped")
        }
    }

    @Test func importAcceptsTabDelimitedFiles() throws {
        let text = "front\tback\nWhat is a joule?\tOne newton-metre.\n"
        let set = try StudySetCSV.importSet(from: text, title: "TSV", now: testNow)

        #expect(set.cards.map(\.question) == ["What is a joule?"])
        #expect(set.cards.map(\.answer) == ["One newton-metre."])
    }

    @Test func importHandlesUTF8BOMAndUTF16Bytes() throws {
        let csv = "question,answer\nq1,a1\nq2,a2\n"

        let utf8BOM = Data([0xEF, 0xBB, 0xBF]) + Data(csv.utf8)
        let fromBOM = try StudySetCSV.importSet(from: utf8BOM, title: "BOM", now: testNow)
        #expect(fromBOM.cards.map(\.question) == ["q1", "q2"])

        let utf16LE = Data([0xFF, 0xFE]) + csv.data(using: .utf16LittleEndian)!
        let fromUTF16LE = try StudySetCSV.importSet(from: utf16LE, title: "LE", now: testNow)
        #expect(fromUTF16LE.cards.map(\.answer) == ["a1", "a2"])

        let utf16BE = Data([0xFE, 0xFF]) + csv.data(using: .utf16BigEndian)!
        let fromUTF16BE = try StudySetCSV.importSet(from: utf16BE, title: "BE", now: testNow)
        #expect(fromUTF16BE.cards.map(\.question) == ["q1", "q2"])
    }

    @Test func importHandlesUTF16WithoutABOM() throws {
        let csv = "question,answer\nq1,a1\n"
        let data = csv.data(using: .utf16LittleEndian)!
        let set = try StudySetCSV.importSet(from: data, title: "No BOM", now: testNow)

        #expect(set.cards.map(\.question) == ["q1"])
        #expect(set.cards.map(\.answer) == ["a1"])
    }
}
