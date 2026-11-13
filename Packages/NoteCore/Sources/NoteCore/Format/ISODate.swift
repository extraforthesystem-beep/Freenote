import Foundation

/// ISO-8601 timestamps with a fractional part, in UTC.
///
/// `ISO8601DateFormatter` stops at milliseconds, which would make
/// `decode(encode(date)) == date` false. This encoder picks the fewest fractional
/// digits (at least nine) that turn back into the exact same `Date`, so a round
/// trip is lossless while the text stays plain ISO-8601. The calendar arithmetic is
/// done by hand so that the output does not depend on locale, time zone or calendar
/// settings: the same date always produces the same bytes on every device.
enum ISODate {
    /// Seconds between 1970-01-01 and 2001-01-01; `Date` counts from the latter.
    private static let referenceOffset = 978_307_200

    /// `2026-11-12T10:22:33.123456789Z`
    ///
    /// The split is taken from `timeIntervalSinceReferenceDate`, not from the
    /// Unix interval: converting a `Date` to Unix seconds and back rounds twice
    /// and can move the value by one unit in the last place, which would break
    /// exact round-tripping.
    static func string(from date: Date) -> String {
        let reference = date.timeIntervalSinceReferenceDate
        guard reference.isFinite else { return text(from: 0, digits: 9) }

        for digits in candidateDigitCounts(for: reference) {
            let candidate = text(from: reference, digits: digits)
            if let parsed = try? self.date(from: candidate), parsed == date {
                return candidate
            }
        }
        // Unreachable for any date a clock produces; the closest text is better
        // than failing to write the file.
        return text(from: reference, digits: 18)
    }

    /// Lowest number of fractional digits that can still resolve one unit in the
    /// last place of `reference`, clamped to 9...18.
    private static func candidateDigitCounts(for reference: Double) -> [Int] {
        guard reference != reference.rounded() else { return [9] }
        let magnitude = abs(reference)
        let needed = Int((17 - log10(magnitude)).rounded(.up))
        let lower = min(18, max(9, needed))
        return Array(lower...18)
    }

    private static func text(from reference: Double, digits: Int) -> String {
        var whole = Int64(reference.rounded(.down))
        var fraction = reference - Double(whole)
        if fraction < 0 {
            fraction += 1
            whole -= 1
        }

        let scale = powerOfTen(digits)
        var units = (fraction * scale).rounded()
        if units >= scale {
            units = 0
            whole += 1
        }

        let seconds = whole + Int64(referenceOffset)
        let day = floorDiv(seconds, 86_400)
        let secondOfDay = seconds - day * 86_400
        let civil = civilFromDays(day)

        return pad(civil.year, 4)
            + "-" + pad(civil.month, 2)
            + "-" + pad(civil.day, 2)
            + "T" + pad(Int(secondOfDay / 3_600), 2)
            + ":" + pad(Int(secondOfDay % 3_600 / 60), 2)
            + ":" + pad(Int(secondOfDay % 60), 2)
            + "." + pad(Int(units), digits)
            + "Z"
    }

    static func date(from string: String) throws -> Date {
        let bytes = Array(string.utf8)
        // Shortest accepted form: 1970-01-01T00:00:00.0Z
        guard bytes.count >= 21, bytes.last == UInt8(ascii: "Z") else {
            throw invalid(string)
        }
        let body = Array(bytes.dropLast())
        guard body.count >= 20 else { throw invalid(string) }

        let year = try number(body, 0, 4)
        guard body[4] == UInt8(ascii: "-") else { throw invalid(string) }
        let month = try number(body, 5, 2)
        guard body[7] == UInt8(ascii: "-") else { throw invalid(string) }
        let day = try number(body, 8, 2)
        guard body[10] == UInt8(ascii: "T") else { throw invalid(string) }
        let hour = try number(body, 11, 2)
        guard body[13] == UInt8(ascii: ":") else { throw invalid(string) }
        let minute = try number(body, 14, 2)
        guard body[16] == UInt8(ascii: ":") else { throw invalid(string) }
        let second = try number(body, 17, 2)

        var fraction = 0.0
        if body.count > 19 {
            guard body[19] == UInt8(ascii: "."), body.count > 20, body.count - 20 <= 18 else {
                throw invalid(string)
            }
            let digits = body.count - 20
            let value = try number(body, 20, digits)
            fraction = Double(value) / powerOfTen(digits)
        }

        guard (1...12).contains(month), (1...31).contains(day),
              (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second)
        else {
            throw invalid(string)
        }

        let total = Int64(daysFromCivil(year: year, month: month, day: day)) * 86_400
            + Int64(hour * 3_600 + minute * 60 + second)
        return Date(timeIntervalSinceReferenceDate: Double(total - Int64(referenceOffset)) + fraction)
    }

    private static func powerOfTen(_ exponent: Int) -> Double {
        var value = 1.0
        for _ in 0..<exponent { value *= 10 }
        return value
    }

    private static func invalid(_ string: String) -> DecodingError {
        DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: [],
                debugDescription: "not an ISO-8601 timestamp: \(string)"
            )
        )
    }

    private static func number(_ bytes: [UInt8], _ offset: Int, _ length: Int) throws -> Int {
        guard offset >= 0, length > 0, offset + length <= bytes.count else {
            throw invalid("")
        }
        var value = 0
        for index in offset..<(offset + length) {
            let byte = bytes[index]
            guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") else {
                throw invalid("")
            }
            value = value * 10 + Int(byte - UInt8(ascii: "0"))
        }
        return value
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let text = String(value)
        guard text.count < width else { return text }
        return String(repeating: "0", count: width - text.count) + text
    }

    private static func floorDiv(_ value: Int64, _ divisor: Int64) -> Int64 {
        let quotient = value / divisor
        return (value % divisor != 0 && (value < 0) != (divisor < 0)) ? quotient - 1 : quotient
    }

    /// Days since 1970-01-01 to a proleptic Gregorian civil date (Howard Hinnant's algorithm).
    private static func civilFromDays(_ days: Int64) -> (year: Int, month: Int, day: Int) {
        let shifted = days + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let year = yearOfEra + era * 400
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthIndex = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
        let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
        return (Int(month <= 2 ? year + 1 : year), Int(month), Int(day))
    }

    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let shiftedYear = month <= 2 ? year - 1 : year
        let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
        let yearOfEra = shiftedYear - era * 400
        let monthIndex = (month + 9) % 12
        let dayOfYear = (153 * monthIndex + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
}
