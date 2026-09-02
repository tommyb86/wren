import Foundation

/// Money is `Int` cents everywhere. Formatting happens only at the display
/// edge, and parsing only at the input edge — nothing in between ever sees a
/// floating-point dollar amount, because repeated rounding is how ledgers drift.
public enum Money {
    /// Formats cents as currency. Negative values keep their sign so variance
    /// can read "-$12.40".
    public static func format(
        cents: Int,
        currencyCode: String = "AUD",
        locale: Locale = Locale(identifier: "en_AU"),
        showsCents: Bool = true
    ) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = locale
        formatter.minimumFractionDigits = showsCents ? 2 : 0
        formatter.maximumFractionDigits = showsCents ? 2 : 0

        let value = NSNumber(value: Double(cents) / 100)
        return formatter.string(from: value) ?? fallbackFormat(cents: cents, showsCents: showsCents)
    }

    /// Rounded to whole dollars — for report headlines, where cents are noise.
    public static func formatWholeDollars(
        cents: Int,
        currencyCode: String = "AUD",
        locale: Locale = Locale(identifier: "en_AU")
    ) -> String {
        format(
            cents: roundToNearestDollar(cents),
            currencyCode: currencyCode,
            locale: locale,
            showsCents: false
        )
    }

    /// swift-corelibs-Foundation's currency formatting differs from Darwin's, so
    /// tests assert against this deterministic form rather than the locale one.
    static func fallbackFormat(cents: Int, showsCents: Bool) -> String {
        let negative = cents < 0
        let magnitude = abs(cents)
        let body: String
        if showsCents {
            body = "\(magnitude / 100).\(String(format: "%02d", magnitude % 100))"
        } else {
            body = "\(magnitude / 100)"
        }
        return "\(negative ? "-" : "")$\(body)"
    }

    static func roundToNearestDollar(_ cents: Int) -> Int {
        let sign = cents < 0 ? -1 : 1
        let magnitude = abs(cents)
        let remainder = magnitude % 100
        let rounded = remainder >= 50 ? magnitude + (100 - remainder) : magnitude - remainder
        return sign * rounded
    }

    /// Parses what someone actually types: "120", "120.50", "$1,234.56", "1 234,56".
    /// Returns nil rather than guessing when the text isn't a number.
    ///
    /// The separator ambiguity is resolved by position: whichever of `.` or `,`
    /// appears last and is followed by exactly one or two digits is the decimal
    /// separator. Everything else is a grouping separator.
    public static func parse(_ text: String) -> Int? {
        let allowed = Set("0123456789.,-")
        let cleaned = text.filter { allowed.contains($0) }
        guard !cleaned.isEmpty else { return nil }

        let negative = cleaned.hasPrefix("-")
        let digitsAndSeparators = cleaned.drop { $0 == "-" }
        guard !digitsAndSeparators.contains("-") else { return nil }

        let decimalIndex = lastDecimalSeparatorIndex(in: String(digitsAndSeparators))

        var whole = ""
        var fraction = ""
        for (offset, character) in digitsAndSeparators.enumerated() {
            guard character.isNumber else { continue }
            if let decimalIndex, offset > decimalIndex {
                fraction.append(character)
            } else {
                whole.append(character)
            }
        }

        guard !whole.isEmpty || !fraction.isEmpty else { return nil }

        let wholeValue = Int(whole.isEmpty ? "0" : whole)
        guard let wholeValue else { return nil }

        // "1.5" is $1.50, not $1.05.
        let paddedFraction = fraction.padding(toLength: 2, withPad: "0", startingAt: 0).prefix(2)
        guard let fractionValue = Int(paddedFraction) else { return nil }

        let magnitude = wholeValue * 100 + fractionValue
        return negative ? -magnitude : magnitude
    }

    private static func lastDecimalSeparatorIndex(in text: String) -> Int? {
        var candidate: Int?
        for (offset, character) in text.enumerated() where character == "." || character == "," {
            let digitsAfter = text.dropFirst(offset + 1).filter(\.isNumber).count
            let separatorsAfter = text.dropFirst(offset + 1).filter { $0 == "." || $0 == "," }.count
            // A decimal separator has 1–2 digits after it and no further separators.
            if separatorsAfter == 0, digitsAfter == 1 || digitsAfter == 2 {
                candidate = offset
            }
        }
        return candidate
    }
}
