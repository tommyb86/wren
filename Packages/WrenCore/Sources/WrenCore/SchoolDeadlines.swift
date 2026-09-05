import Foundation

/// A date pulled out of a notice body, with the text it came from so the parent
/// can check it before trusting it. Extraction proposes; it never commits — a
/// wrong reminder you cannot trace is worse than no reminder.
public struct SchoolDeadline: Hashable, Sendable {
    public let date: Date
    /// The block of body text the date was found in — shown as evidence.
    public let evidence: String
    public let confidence: Confidence

    public enum Confidence: String, Sendable, Hashable {
        /// The year was written out.
        case high
        /// Day and month were given; the year was inferred.
        case medium
    }

    public init(date: Date, evidence: String, confidence: Confidence) {
        self.date = date
        self.evidence = evidence
        self.confidence = confidence
    }
}

public enum SchoolDeadlines {
    /// Words that mark a block as carrying an actual obligation or event, rather
    /// than a date mentioned in passing. A date with no cue is not suggested.
    private static let cues = [
        "clos", "deadline", "due", "rsvp", "register", "sign up", "sign-up",
        "order", "last day", "submit", "return", "book", "pay",
        "assembly", "concert", "excursion", "incursion", "meeting", "photo",
        "gala", "showcase", "tour", "starts", "commence", "begins", "open until"
    ]

    private static let monthNumbers: [String: Int] = [
        "january": 1, "jan": 1, "february": 2, "feb": 2, "march": 3, "mar": 3,
        "april": 4, "apr": 4, "may": 5, "june": 6, "jun": 6, "july": 7, "jul": 7,
        "august": 8, "aug": 8, "september": 9, "sept": 9, "sep": 9,
        "october": 10, "oct": 10, "november": 11, "nov": 11, "december": 12, "dec": 12
    ]

    private static let monthAlternation =
        "january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sept|sep|oct|nov|dec"

    /// Extracts deadlines from a notice's structured body blocks. Working on
    /// blocks rather than the flattened text matters: flattening fuses "Closing
    /// Date" onto "Thursday 24 September" with no boundary, so the evidence is
    /// only legible per block.
    public static func extract(
        fromHTML html: String,
        published: Date?,
        calendar: Calendar = .current
    ) -> [SchoolDeadline] {
        let blocks = SchoolBody.blocks(fromHTML: html).map(\.text)
        return extract(fromBlocks: blocks, published: published, calendar: calendar)
    }

    public static func extract(
        fromBlocks blocks: [String],
        published: Date?,
        calendar: Calendar = .current
    ) -> [SchoolDeadline] {
        let reference = published ?? Date()
        var found: [SchoolDeadline] = []
        var seenDays = Set<Date>()

        for block in blocks {
            let lower = block.lowercased()
            guard cues.contains(where: { lower.contains($0) }) else { continue }

            for candidate in dates(in: block, reference: reference, calendar: calendar) {
                let day = calendar.startOfDay(for: candidate.date)
                guard !seenDays.contains(day) else { continue }
                seenDays.insert(day)
                found.append(
                    SchoolDeadline(
                        date: candidate.date,
                        evidence: block.trimmingCharacters(in: .whitespacesAndNewlines),
                        confidence: candidate.confidence
                    )
                )
            }
        }
        return found.sorted { $0.date < $1.date }
    }

    // MARK: - Date parsing

    private struct Candidate { let date: Date; let confidence: SchoolDeadline.Confidence }

    /// "24 September 2026" (high) or "24 September" with the year inferred
    /// (medium). Australian day-first ordering; ordinal suffixes tolerated.
    private static func dates(in text: String, reference: Date, calendar: Calendar) -> [Candidate] {
        guard let regex = try? NSRegularExpression(
            pattern: "\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+(\(monthAlternation))\\b(?:\\s+(\\d{4}))?",
            options: [.caseInsensitive]
        ) else { return [] }

        let ns = text as NSString
        var results: [Candidate] = []
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let day = Int(ns.substring(with: m.range(at: 1))),
                  let month = monthNumbers[ns.substring(with: m.range(at: 2)).lowercased()] else { continue }

            let yearRange = m.range(at: 3)
            if yearRange.location != NSNotFound, let year = Int(ns.substring(with: yearRange)) {
                if let date = makeDate(year: year, month: month, day: day, calendar: calendar) {
                    results.append(Candidate(date: date, confidence: .high))
                }
            } else if let date = inferYear(month: month, day: day, reference: reference, calendar: calendar) {
                results.append(Candidate(date: date, confidence: .medium))
            }
        }
        return results
    }

    private static func makeDate(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    }

    /// Chooses the year that puts a bare "day month" in the near future relative
    /// to when the notice was posted — so "5 February" in a November notice is
    /// next February, not ten months ago.
    private static func inferYear(month: Int, day: Int, reference: Date, calendar: Calendar) -> Date? {
        let baseYear = calendar.component(.year, from: reference)
        guard let candidate = makeDate(year: baseYear, month: month, day: day, calendar: calendar) else { return nil }
        if candidate < calendar.date(byAdding: .day, value: -60, to: reference)! {
            return makeDate(year: baseYear + 1, month: month, day: day, calendar: calendar)
        }
        return candidate
    }
}
