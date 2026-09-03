import Foundation
import WrenCore

/// CSV export via the share sheet. Amounts are written as plain decimal numbers
/// with no currency symbol or grouping, because the destination is a
/// spreadsheet, not a reader.
enum BillCSV {
    /// Every bill with its normalised figures — the "what do we spend" export.
    static func bills(_ specs: [BillSpec]) -> String {
        var rows = [
            row("Name", "Category", "Paid by", "Amount", "Cadence", "Varies", "Monthly equivalent", "Annual", "Active")
        ]

        for spec in specs.sorted(by: { $0.name < $1.name }) {
            rows.append(row(
                spec.name,
                spec.category,
                spec.paidBy,
                decimal(spec.amountCents),
                BillingPeriod.cadenceDescription(spec.schedule),
                spec.isVariableAmount ? "yes" : "no",
                decimal(BillingPeriod.monthlyEquivalentCents(amountCents: spec.amountCents, schedule: spec.schedule)),
                decimal(BillingPeriod.annualCents(amountCents: spec.amountCents, schedule: spec.schedule)),
                spec.isActive ? "yes" : "no"
            ))
        }
        return rows.joined(separator: "\n")
    }

    /// Payment history across every bill, with the variance per payment.
    static func payments(_ specs: [BillSpec], payments: [BillPaymentRecord]) -> String {
        let names = Dictionary(uniqueKeysWithValues: specs.map { ($0.id, $0.name) })
        let owners = Dictionary(uniqueKeysWithValues: specs.map { ($0.id, $0.paidBy) })
        let expected = Dictionary(uniqueKeysWithValues: specs.map { ($0.id, $0.amountCents) })

        // Owner is its own column rather than folded into the name — a
        // spreadsheet wants to filter and pivot on it.
        var rows = [row("Bill", "Paid by", "Due date", "Paid on", "Expected", "Paid", "Difference")]

        for payment in payments.sorted(by: { $0.dueDate > $1.dueDate }) {
            let expectedCents = expected[payment.billID] ?? 0
            rows.append(row(
                names[payment.billID] ?? "Unknown",
                owners[payment.billID] ?? "",
                iso(payment.dueDate),
                iso(payment.paidAt),
                decimal(expectedCents),
                decimal(payment.amountCents),
                decimal(payment.amountCents - expectedCents)
            ))
        }
        return rows.joined(separator: "\n")
    }

    /// The 12-month forecast, one row per month.
    static func forecast(_ months: [ForecastMonth]) -> String {
        var rows = [row("Month", "Bills due", "Total")]
        for month in months {
            rows.append(row(
                monthKey(month.monthStart),
                String(month.occurrences.count),
                decimal(month.totalCents)
            ))
        }
        return rows.joined(separator: "\n")
    }

    // MARK: - Helpers

    /// Cents as a plain decimal: 12050 -> "120.50".
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

    private static func monthKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }

    private static func row(_ fields: String...) -> String {
        fields.map(escape).joined(separator: ",")
    }

    /// RFC 4180: quote anything containing a comma, quote or newline, and double
    /// up embedded quotes. A bill named `Power, off-peak` would otherwise shift
    /// every column after it.
    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
