import Foundation

/// What the parser thinks it found on a receipt.
///
/// Every field is optional and every guess keeps its alternatives, because
/// these are **suggestions the user confirms** — never silent auto-fill. OCR on
/// a crumpled receipt gets things wrong often enough that quietly saving a
/// wrong amount would poison the records it exists to keep.
public struct ReceiptSuggestions: Hashable, Sendable {
    public let vendor: String?
    public let totalCents: Int?
    public let date: Date?
    /// Other plausible amounts, best first, for a picker.
    public let candidateTotals: [Int]
    /// Other plausible dates, most recent first.
    public let candidateDates: [Date]

    public var isEmpty: Bool {
        vendor == nil && totalCents == nil && date == nil
    }
}

/// Pulls a vendor, a total and a date out of OCR text.
///
/// Pure string work on Foundation, so the whole thing is testable on any
/// platform — which matters because the Vision framework that produces this
/// text only exists on the device.
public enum ReceiptParser {

    /// Amounts must carry cents. Receipt OCR is full of bare integers — ABNs,
    /// phone numbers, item counts, loyalty points — and requiring a decimal
    /// pair removes nearly all of them.
    private static let amountPattern = #"\$?\s?(\d{1,3}(?:,\d{3})+|\d+)\.(\d{2})\b"#

    /// Lines that name the figure being looked for.
    private static let totalKeywords = ["AMOUNT DUE", "BALANCE DUE", "AMOUNT PAID", "TOTAL DUE", "TOTAL"]
    /// Lines that contain an amount which is definitely not the total.
    private static let notTotalKeywords = [
        "SUBTOTAL", "SUB TOTAL", "SUB-TOTAL", "GST", "TAX", "SAVINGS", "SAVED",
        "CHANGE", "CASH", "TENDER", "ROUNDING", "DISCOUNT", "BALANCE OWING"
    ]
    /// Header noise that is never the trader's name.
    private static let vendorNoise = [
        "TAX INVOICE", "INVOICE", "RECEIPT", "ABN", "ACN", "PHONE", "TEL", "PH:",
        "EFTPOS", "MERCHANT", "CUSTOMER COPY", "DUPLICATE", "THANK YOU", "GST",
        "WWW.", "HTTP", "ORDER", "TERMINAL"
    ]

    public static func parse(
        _ text: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ReceiptSuggestions {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let totals = rankedTotals(in: lines)
        let dates = plausibleDates(in: lines, now: now, calendar: calendar)

        return ReceiptSuggestions(
            vendor: vendor(in: lines),
            totalCents: totals.first,
            date: dates.first,
            candidateTotals: totals,
            candidateDates: dates
        )
    }

    // MARK: - Totals

    /// Amounts found on the receipt, best guess first.
    ///
    /// Scored rather than filtered: a mangled total line shouldn't leave the
    /// user with nothing to pick from, so everything stays as a candidate and
    /// only the order changes.
    static func rankedTotals(in lines: [String]) -> [Int] {
        var scored: [(cents: Int, score: Int)] = []

        for line in lines {
            let upper = line.uppercased()
            let amounts = amounts(in: line)
            guard !amounts.isEmpty else { continue }

            var score = 0
            if totalKeywords.contains(where: { upper.contains($0) }) { score += 100 }
            if notTotalKeywords.contains(where: { upper.contains($0) }) { score -= 120 }

            for cents in amounts {
                scored.append((cents, score))
            }
        }

        // Highest score first, then largest amount — on an unscored receipt the
        // total is almost always the biggest number on it.
        return scored
            .sorted { $0.score == $1.score ? $0.cents > $1.cents : $0.score > $1.score }
            .map(\.cents)
            .deduplicated()
    }

    static func amounts(in line: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: amountPattern) else { return [] }
        let range = NSRange(line.startIndex..., in: line)

        return regex.matches(in: line, range: range).compactMap { match in
            guard let whole = substring(line, match.range(at: 1)),
                  let fraction = substring(line, match.range(at: 2))
            else { return nil }
            return Money.parse("\(whole).\(fraction)")
        }
    }

    // MARK: - Dates

    /// Valid, non-future dates found on the receipt, most recent first.
    ///
    /// Receipts carry several dates — card expiry, "valid until", ABN
    /// registration — so anything in the future is dropped, and the most recent
    /// of what remains is the best guess at when the purchase happened.
    static func plausibleDates(in lines: [String], now: Date, calendar: Calendar) -> [Date] {
        let text = lines.joined(separator: "\n")
        var found: [Date] = []

        found += numericDates(in: text, calendar: calendar)
        found += writtenDates(in: text, calendar: calendar)

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let floor = calendar.date(byAdding: .year, value: -15, to: now) ?? now

        return found
            .filter { $0 <= tomorrow && $0 >= floor }
            .sorted(by: >)
            .deduplicated()
    }

    /// Day-first, because this is Australia: 03/09/2026 is 3 September.
    private static func numericDates(in text: String, calendar: Calendar) -> [Date] {
        let pattern = #"\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let day = substring(text, match.range(at: 1)).flatMap(Int.init),
                  let month = substring(text, match.range(at: 2)).flatMap(Int.init),
                  let rawYear = substring(text, match.range(at: 3)).flatMap(Int.init)
            else { return nil }
            return date(day: day, month: month, rawYear: rawYear, calendar: calendar)
        }
    }

    /// "3 Sep 2026" and "Sep 3, 2026".
    private static func writtenDates(in text: String, calendar: Calendar) -> [Date] {
        var result: [Date] = []

        let dayFirst = #"\b(\d{1,2})\s+([A-Za-z]{3,9})\.?,?\s+(\d{2,4})\b"#
        if let regex = try? NSRegularExpression(pattern: dayFirst) {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let day = substring(text, match.range(at: 1)).flatMap(Int.init),
                      let name = substring(text, match.range(at: 2)),
                      let month = monthNumber(name),
                      let rawYear = substring(text, match.range(at: 3)).flatMap(Int.init)
                else { continue }
                if let parsed = date(day: day, month: month, rawYear: rawYear, calendar: calendar) {
                    result.append(parsed)
                }
            }
        }

        let monthFirst = #"\b([A-Za-z]{3,9})\.?\s+(\d{1,2}),?\s+(\d{2,4})\b"#
        if let regex = try? NSRegularExpression(pattern: monthFirst) {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let name = substring(text, match.range(at: 1)),
                      let month = monthNumber(name),
                      let day = substring(text, match.range(at: 2)).flatMap(Int.init),
                      let rawYear = substring(text, match.range(at: 3)).flatMap(Int.init)
                else { continue }
                if let parsed = date(day: day, month: month, rawYear: rawYear, calendar: calendar) {
                    result.append(parsed)
                }
            }
        }
        return result
    }

    private static func monthNumber(_ name: String) -> Int? {
        let names = [
            "JAN", "FEB", "MAR", "APR", "MAY", "JUN",
            "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"
        ]
        let key = String(name.uppercased().prefix(3))
        guard let index = names.firstIndex(of: key) else { return nil }
        return index + 1
    }

    /// Builds a date only if the components are real — rejects 32/13, and
    /// rejects 31 February rather than rolling it into March.
    private static func date(day: Int, month: Int, rawYear: Int, calendar: Calendar) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        // Two digits means this century. Receipts are not from the nineties.
        let year = rawYear < 100 ? 2000 + rawYear : rawYear

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12 // midday, so a timezone shift can't move the day

        guard let candidate = calendar.date(from: components),
              calendar.component(.day, from: candidate) == day,
              calendar.component(.month, from: candidate) == month
        else { return nil }
        return candidate
    }

    // MARK: - Vendor

    /// The trader's name is nearly always in the first few lines, above the
    /// address and below nothing.
    static func vendor(in lines: [String]) -> String? {
        for line in lines.prefix(6) {
            let upper = line.uppercased()
            guard !vendorNoise.contains(where: { upper.contains($0) }) else { continue }

            let letters = line.filter(\.isLetter).count
            let digits = line.filter(\.isNumber).count
            // Needs real words, and shouldn't be mostly digits — that's an ABN,
            // a phone number or a till code.
            guard letters >= 3, letters > digits else { continue }
            guard amounts(in: line).isEmpty else { continue }

            let cleaned = line
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return cleaned.isEmpty ? nil : cleaned
        }
        return nil
    }

    // MARK: - Helpers

    private static func substring(_ source: String, _ range: NSRange) -> String? {
        guard range.location != NSNotFound, let swiftRange = Range(range, in: source) else { return nil }
        return String(source[swiftRange])
    }
}

extension Array where Element: Hashable {
    /// Order-preserving unique.
    func deduplicated() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
