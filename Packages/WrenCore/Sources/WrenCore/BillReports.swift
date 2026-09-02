import Foundation

// MARK: - Inputs

/// A bill, decoupled from SwiftData so every report is testable without a model
/// container.
public struct BillSpec: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    /// The expected amount. For variable bills (electricity, water) this is an
    /// estimate, and the variance report is where that shows.
    public let amountCents: Int
    public let isVariableAmount: Bool
    public let schedule: Schedule
    public let category: String
    public let isActive: Bool

    public init(
        id: UUID,
        name: String,
        amountCents: Int,
        isVariableAmount: Bool = false,
        schedule: Schedule,
        category: String = "",
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.amountCents = amountCents
        self.isVariableAmount = isVariableAmount
        self.schedule = schedule
        self.category = category
        self.isActive = isActive
    }
}

/// What was actually paid, against the occurrence it settles. Recording both the
/// expected and the actual amount is what makes the reports honest — variance is
/// the interesting signal.
public struct BillPaymentRecord: Hashable, Sendable {
    public let billID: UUID
    public let amountCents: Int
    public let dueDate: Date
    public let paidAt: Date

    public init(billID: UUID, amountCents: Int, dueDate: Date, paidAt: Date) {
        self.billID = billID
        self.amountCents = amountCents
        self.dueDate = dueDate
        self.paidAt = paidAt
    }
}

// MARK: - Outputs

public struct CategoryTotal: Hashable, Sendable, Identifiable {
    public let category: String
    public let monthlyCents: Int
    public let annualCents: Int
    public let billCount: Int

    public var id: String { category }
}

/// One occurrence in a month, and whether it has been settled.
public struct BillOccurrence: Hashable, Sendable, Identifiable {
    public let billID: UUID
    public let name: String
    public let dueDate: Date
    public let expectedCents: Int
    public let paidCents: Int?

    public var isPaid: Bool { paidCents != nil }
    /// What is still owed on this occurrence.
    public var outstandingCents: Int { isPaid ? 0 : expectedCents }
    public var id: String { "\(billID.uuidString)-\(dueDate.timeIntervalSince1970)" }
}

public struct MonthSummary: Hashable, Sendable {
    public let monthStart: Date
    public let occurrences: [BillOccurrence]

    /// Expected total for everything falling in the month.
    public var dueCents: Int { occurrences.reduce(0) { $0 + $1.expectedCents } }
    /// Actual total paid, which can exceed `dueCents` on variable bills.
    public var paidCents: Int { occurrences.reduce(0) { $0 + ($1.paidCents ?? 0) } }
    public var outstandingCents: Int { occurrences.reduce(0) { $0 + $1.outstandingCents } }
}

/// A month in the forecast. The point is seeing the lumpy ones — rego,
/// insurance — before they arrive.
public struct ForecastMonth: Hashable, Sendable, Identifiable {
    public let monthStart: Date
    public let occurrences: [BillOccurrence]

    public var totalCents: Int { occurrences.reduce(0) { $0 + $1.expectedCents } }
    public var id: Date { monthStart }
}

/// Expected versus actual for one bill.
public struct BillVariance: Hashable, Sendable {
    public let billID: UUID
    public let expectedCents: Int
    public let actualCents: Int
    public let paymentCount: Int

    /// Positive means it cost more than expected.
    public var differenceCents: Int { actualCents - expectedCents }

    public var percentDifference: Double? {
        guard expectedCents != 0 else { return nil }
        return (Double(differenceCents) / Double(expectedCents)) * 100
    }
}

// MARK: - Reports

/// The point of bills is knowing what the household spends, so this is a
/// reporting system rather than a reminder one.
public enum BillReports {

    // MARK: Headline figures

    /// Sum of monthly-equivalents across active bills — the "what do we spend"
    /// number.
    public static func monthlyCommitmentCents(_ bills: [BillSpec]) -> Int {
        active(bills).reduce(0) {
            $0 + BillingPeriod.monthlyEquivalentCents(amountCents: $1.amountCents, schedule: $1.schedule)
        }
    }

    public static func annualCommitmentCents(_ bills: [BillSpec]) -> Int {
        active(bills).reduce(0) {
            $0 + BillingPeriod.annualCents(amountCents: $1.amountCents, schedule: $1.schedule)
        }
    }

    // MARK: By category

    /// Grouped monthly-equivalents, largest first. Uncategorised bills collect
    /// under a single explicit label rather than an empty string.
    public static func byCategory(_ bills: [BillSpec], uncategorisedLabel: String = "Uncategorised") -> [CategoryTotal] {
        let grouped = Dictionary(grouping: active(bills)) { bill in
            bill.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? uncategorisedLabel
                : bill.category
        }

        return grouped
            .map { category, bills in
                CategoryTotal(
                    category: category,
                    monthlyCents: monthlyCommitmentCents(bills),
                    annualCents: annualCommitmentCents(bills),
                    billCount: bills.count
                )
            }
            .sorted {
                $0.monthlyCents == $1.monthlyCents
                    ? $0.category < $1.category
                    : $0.monthlyCents > $1.monthlyCents
            }
    }

    // MARK: This month

    /// What's due this month, what's paid, what's outstanding.
    public static func monthSummary(
        bills: [BillSpec],
        payments: [BillPaymentRecord],
        containing date: Date,
        calendar: Calendar = .current
    ) -> MonthSummary {
        guard let month = calendar.dateInterval(of: .month, for: date) else {
            return MonthSummary(monthStart: date, occurrences: [])
        }
        let end = month.end.addingTimeInterval(-1)
        return MonthSummary(
            monthStart: month.start,
            occurrences: occurrences(
                bills: bills,
                payments: payments,
                from: month.start,
                to: end,
                calendar: calendar
            )
        )
    }

    // MARK: Forecast

    /// `months` months from the month containing `from`, so lumpy months are
    /// visible before they land.
    public static func forecast(
        bills: [BillSpec],
        payments: [BillPaymentRecord] = [],
        from: Date,
        months: Int = 12,
        calendar: Calendar = .current
    ) -> [ForecastMonth] {
        guard months > 0, let firstMonth = calendar.dateInterval(of: .month, for: from) else { return [] }

        return (0..<months).compactMap { offset -> ForecastMonth? in
            guard let monthStart = calendar.date(byAdding: .month, value: offset, to: firstMonth.start),
                  let month = calendar.dateInterval(of: .month, for: monthStart)
            else { return nil }

            return ForecastMonth(
                monthStart: month.start,
                occurrences: occurrences(
                    bills: bills,
                    payments: payments,
                    from: month.start,
                    to: month.end.addingTimeInterval(-1),
                    calendar: calendar
                )
            )
        }
    }

    /// The average forecast month — useful as a baseline to show which months
    /// are the expensive ones.
    public static func averageMonthlyCents(_ forecast: [ForecastMonth]) -> Int {
        guard !forecast.isEmpty else { return 0 }
        let total = forecast.reduce(0) { $0 + $1.totalCents }
        return Int((Double(total) / Double(forecast.count)).rounded())
    }

    // MARK: History and variance

    /// One bill's payments, newest first — so "has the power bill gone up?" is
    /// answerable.
    public static func history(billID: UUID, payments: [BillPaymentRecord]) -> [BillPaymentRecord] {
        payments
            .filter { $0.billID == billID }
            .sorted { $0.dueDate > $1.dueDate }
    }

    /// Expected versus actual across every recorded payment for a bill.
    ///
    /// Expected is the bill's amount times the number of payments — comparing
    /// like with like, rather than against a period the payments don't cover.
    public static func variance(
        bill: BillSpec,
        payments: [BillPaymentRecord]
    ) -> BillVariance {
        let mine = payments.filter { $0.billID == bill.id }
        return BillVariance(
            billID: bill.id,
            expectedCents: bill.amountCents * mine.count,
            actualCents: mine.reduce(0) { $0 + $1.amountCents },
            paymentCount: mine.count
        )
    }

    /// Variances across every bill with at least one payment, worst overspend
    /// first.
    public static func variances(
        bills: [BillSpec],
        payments: [BillPaymentRecord]
    ) -> [BillVariance] {
        bills
            .map { variance(bill: $0, payments: payments) }
            .filter { $0.paymentCount > 0 }
            .sorted { $0.differenceCents > $1.differenceCents }
    }

    // MARK: - Shared

    /// Dated occurrences in a window, matched against payments. Respects
    /// `endDate`, because these are real occurrences rather than a rate.
    public static func occurrences(
        bills: [BillSpec],
        payments: [BillPaymentRecord],
        from: Date,
        to: Date,
        calendar: Calendar = .current
    ) -> [BillOccurrence] {
        active(bills)
            .flatMap { bill -> [BillOccurrence] in
                let mine = payments.filter { $0.billID == bill.id }
                return ScheduleEngine.occurrences(bill.schedule, from: from, to: to, calendar: calendar)
                    .map { due in
                        // Matched at day granularity, so editing a bill's due
                        // time doesn't orphan a recorded payment.
                        let payment = mine.first {
                            calendar.startOfDay(for: $0.dueDate) == calendar.startOfDay(for: due)
                        }
                        return BillOccurrence(
                            billID: bill.id,
                            name: bill.name,
                            dueDate: due,
                            expectedCents: bill.amountCents,
                            paidCents: payment?.amountCents
                        )
                    }
            }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private static func active(_ bills: [BillSpec]) -> [BillSpec] {
        bills.filter(\.isActive)
    }
}
