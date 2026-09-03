import Foundation
import WrenCore

/// CSV export for one financial year — the actual payoff of the whole feature,
/// at tax time.
enum ReceiptCSV {
    static func rows(_ receipts: [Receipt], calendar: Calendar = .current) -> String {
        var lines = [row("Date", "Vendor", "Amount", "Category", "Financial year", "Pages", "Notes")]

        for receipt in receipts.sorted(by: { $0.date < $1.date }) {
            lines.append(row(
                iso(receipt.date),
                receipt.vendor,
                decimal(receipt.amountCents),
                receipt.category,
                receipt.financialYear(calendar: calendar).label,
                String(receipt.pageCount),
                receipt.notes
            ))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    /// Plain decimals with no symbol or grouping: the destination is a
    /// spreadsheet, not a reader.
    private static func decimal(_ cents: Int) -> String {
        let negative = cents < 0
        let magnitude = abs(cents)
        return "\(negative ? "-" : "")\(magnitude / 100).\(String(format: "%02d", magnitude % 100))"
    }

    private static func iso(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func row(_ fields: String...) -> String {
        fields.map(escape).joined(separator: ",")
    }

    /// RFC 4180. Receipt notes are free text and vendor names come from OCR, so
    /// commas, quotes and stray newlines are all likely.
    private static func escape(_ field: String) -> String {
        let flattened = field.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        guard flattened.contains(",") || flattened.contains("\"") else { return flattened }
        return "\"\(flattened.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
