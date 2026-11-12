import Foundation

/// CSV import and export for study cards.
///
/// The format is deliberately small: a header naming the two fields, followed
/// by one record per card. The header may be `question,answer`, `front,back`
/// or `term,definition`, matched case-insensitively. Fields follow RFC 4180
/// quoting, so commas, double quotes and newlines survive a round trip. Import
/// also accepts tab-delimited files and CRLF, LF or lone CR line endings.
/// Export always writes `question,answer` CSV with CRLF line endings.
public enum StudySetCSV {
    /// Header names accepted for the question column.
    private static let questionHeaders: Set<String> = ["question", "front", "term"]
    /// Header names accepted for the answer column.
    private static let answerHeaders: Set<String> = ["answer", "back", "definition"]
    private struct ParsedRow {
        var fields: [String]
        var line: Int
    }

    /// Renders a set as RFC 4180 CSV, including a trailing CRLF.
    ///
    /// Only question and answer are exported; ids, images, source links and
    /// timestamps stay in the study set file.
    public static func export(_ set: StudySet) -> String {
        var rows = ["question,answer"]
        rows.reserveCapacity(set.cards.count + 1)
        for card in set.cards {
            rows.append(escape(card.question) + "," + escape(card.answer))
        }
        return rows.joined(separator: "\r\n") + "\r\n"
    }

    /// Parses a two-column study CSV into a new set.
    ///
    /// Every imported card gets a fresh id and the same `now` timestamp. The
    /// header is matched case-insensitively after trimming surrounding
    /// whitespace, and may be `question,answer`, `front,back` or
    /// `term,definition`; tab-delimited files are accepted too. Malformed input
    /// throws a ``StudyKitError`` with the row and, where useful, the column of
    /// the problem.
    public static func importSet(
        from text: String,
        title: String,
        id: UUID = UUID(),
        now: Date = Date()
    ) throws -> StudySet {
        var input = text
        if input.first == "\u{FEFF}" {
            input.removeFirst()
        }

        let rows = try parseRows(input, delimiter: delimiter(in: input))
        guard let header = rows.first else {
            throw StudyKitError.emptyCSV
        }

        let names = header.fields.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        guard names.count == 2,
              questionHeaders.contains(names[0]),
              answerHeaders.contains(names[1])
        else {
            throw StudyKitError.invalidCSVHeader(found: header.fields)
        }

        var cards: [StudyCard] = []
        cards.reserveCapacity(rows.count - 1)
        for row in rows.dropFirst() {
            guard row.fields.count == 2 else {
                throw StudyKitError.wrongFieldCount(
                    row: row.line,
                    expected: 2,
                    found: row.fields.count
                )
            }
            cards.append(
                StudyCard(
                    question: row.fields[0],
                    answer: row.fields[1],
                    createdAt: now,
                    updatedAt: now
                )
            )
        }

        return StudySet(id: id, title: title, cards: cards, createdAt: now, updatedAt: now)
    }

    /// Decodes bytes from a study file, tolerating a UTF-8 BOM and UTF-16.
    ///
    /// Files exported by Numbers, Excel and some web tools arrive as UTF-16 or
    /// with a byte-order mark; both are read here rather than failing the import.
    public static func decodeText(_ data: Data) -> String? {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(data: data, encoding: .utf8)
        }
        // UTF-16 without a BOM: text has a null byte in every other position,
        // and plain UTF-8 never does, so check that before trusting UTF-8.
        if let nul = data.prefix(64).firstIndex(of: 0x00) {
            let littleEndian = data.distance(from: data.startIndex, to: nul) % 2 == 1
            if let text = String(
                data: data,
                encoding: littleEndian ? .utf16LittleEndian : .utf16BigEndian
            ) {
                return text
            }
        }
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let utf16 = String(data: data, encoding: .utf16) {
            return utf16
        }
        return String(data: data, encoding: .isoLatin1)
    }

    /// Parses study CSV from raw file bytes, detecting common encodings first.
    public static func importSet(
        from data: Data,
        title: String,
        id: UUID = UUID(),
        now: Date = Date()
    ) throws -> StudySet {
        guard let text = decodeText(data) else {
            throw StudyKitError.emptyCSV
        }
        return try importSet(from: text, title: title, id: id, now: now)
    }

    // MARK: - Writing

    private static func escape(_ field: String) -> String {
        // Scalars, not Characters: a CRLF-only field is one Character and would
        // otherwise slip through unquoted.
        let needsQuotes = field.unicodeScalars.contains { scalar in
            scalar == "," || scalar == "\"" || scalar == "\n" || scalar == "\r"
        }
        guard needsQuotes else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - Reading

    /// Picks the field separator from the first physical line: a header with a
    /// tab and no comma is tab-delimited, everything else is comma-delimited.
    private static func delimiter(in text: String) -> Unicode.Scalar {
        var commas = 0
        var tabs = 0
        for scalar in text.unicodeScalars {
            if scalar == "\n" || scalar == "\r" { break }
            if scalar == "," { commas += 1 }
            if scalar == "\t" { tabs += 1 }
        }
        return tabs > 0 && commas == 0 ? "\t" : ","
    }

    /// A small RFC 4180 scanner. Records are returned with the physical line
    /// they start on, so errors point at the source text rather than at an
    /// index into a filtered list.
    private static func parseRows(_ text: String, delimiter: Unicode.Scalar) throws -> [ParsedRow] {
        // Unicode scalars, not Characters: Swift folds CRLF into one Character,
        // which would hide the line breaks this scanner depends on.
        let scalars = Array(text.unicodeScalars)
        var rows: [ParsedRow] = []
        var index = 0
        var line = 1

        while index < scalars.count {
            let recordLine = line
            let recordStart = index
            var fields: [String] = []
            var field = ""
            var inQuotes = false
            var afterQuote = false
            var sawContent = false
            var finished = false

            recordLoop: while index < scalars.count {
                let scalar = scalars[index]

                if inQuotes {
                    if scalar == "\"" {
                        if index + 1 < scalars.count, scalars[index + 1] == "\"" {
                            field.unicodeScalars.append("\"")
                            index += 2
                        } else {
                            inQuotes = false
                            afterQuote = true
                            index += 1
                        }
                    } else {
                        if scalar == "\n" {
                            line += 1
                        } else if scalar == "\r" {
                            let isCRLF = index + 1 < scalars.count && scalars[index + 1] == "\n"
                            if !isCRLF { line += 1 }
                        }
                        field.unicodeScalars.append(scalar)
                        index += 1
                    }
                    continue
                }

                if afterQuote {
                    switch scalar {
                    case delimiter:
                        fields.append(field)
                        field = ""
                        afterQuote = false
                        sawContent = true
                        index += 1
                    case "\r":
                        index += 1
                        if index < scalars.count, scalars[index] == "\n" {
                            index += 1
                        }
                        fields.append(field)
                        line += 1
                        finished = true
                        break recordLoop
                    case "\n":
                        index += 1
                        fields.append(field)
                        line += 1
                        finished = true
                        break recordLoop
                    default:
                        throw StudyKitError.unexpectedCharacterAfterQuote(
                            row: recordLine,
                            column: index - recordStart + 1
                        )
                    }
                    continue
                }

                switch scalar {
                case delimiter:
                    fields.append(field)
                    field = ""
                    sawContent = true
                    index += 1
                case "\r":
                    index += 1
                    if index < scalars.count, scalars[index] == "\n" {
                        index += 1
                    }
                    fields.append(field)
                    line += 1
                    finished = true
                    break recordLoop
                case "\n":
                    index += 1
                    fields.append(field)
                    line += 1
                    finished = true
                    break recordLoop
                case "\"":
                    guard field.isEmpty else {
                        throw StudyKitError.unexpectedQuote(
                            row: recordLine,
                            column: index - recordStart + 1
                        )
                    }
                    inQuotes = true
                    sawContent = true
                    index += 1
                default:
                    field.unicodeScalars.append(scalar)
                    sawContent = true
                    index += 1
                }
            }

            if inQuotes {
                throw StudyKitError.unterminatedQuotedField(row: recordLine)
            }
            if !finished {
                fields.append(field)
            }
            if sawContent {
                rows.append(ParsedRow(fields: fields, line: recordLine))
            }
        }

        return rows
    }
}
