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
    /// Optional, for a shared household. Carried through to occurrences because
    /// two people can hold separate bills with identical names — two car
    /// registrations are only tellable apart by whose it is.
    public let paidBy: String
    /// Direct debit. Occurrences past their due date are treated as settled so
    /// there is nothing to tick — but the *amount* is never invented, because
    /// Wren has no bank feed and cannot know a debit actually went through.
    public let paysAutomatically: Bool
    public let isActive: Bool

    public init(
        id: UUID,
        name: String,
        amountCents: Int,
        isVariableAmount: Bool = false,
        schedule: Schedule,
        category: String = "",
        paidBy: String = "",
        paysAutomatically: Bool = false,
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.amountCents = amountCents
        self.isVariableAmount = isVariableAmount
        self.schedule = schedule
        self.category = category
        self.paidBy = paidBy
        self.paysAutomatically = paysAutomatically
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

/// One occurrence in a month, and how it stands.
public struct BillOccurrence: Hashable, Sendable, Identifiable {
    /// "Is it settled?" and "what was actually paid?" are two different
    /// questions, and a direct debit answers only the first. Collapsing them
    /// would mean inventing an amount nobody verified.
    public enum Settlement: Hashable, Sendable {
        /// Still owed, or not yet due.
        case outstanding
        /// A real payment was recorded, for this much.
        case recorded(cents: Int)
        /// A direct debit whose due date has passed. Presumed to have gone out;
        /// the amount was never verified.
        case assumed
    }

    public let billID: UUID
    public let name: String
    /// Whose bill it is, when the household records that.
    public let paidBy: String
    public let isVariableAmount: Bool
    public let dueDate: Date
    public let expectedCents: Int
    public let settlement: Settlement

    /// Name qualified by owner, so two "Car registration" rows are tellable
    /// apart in a list without opening either.
    public var label: String {
        paidBy.isEmpty ? name : "\(name) · \(paidBy)"
    }

    /// What was actually paid — only ever a figure someone recorded.
    public var recordedCents: Int? {
        guard case .recorded(let cents) = settlement else { return nil }
        return cents
    }

    public var isSettled: Bool { settlement != .outstanding }
    public var isAssumed: Bool { settlement == .assumed }

    /// What is still owed on this occurrence.
    public var outstandingCents: Int { isSettled ? 0 : expectedCents }

    /// Best available figure for money-out totals: the recorded amount when
    /// known, otherwise the expectation for an assumed debit.
    public var settledCents: Int {
        switch settlement {
        case .outstanding: return 0
        case .recorded(let cents): return cents
        case .assumed: return expectedCents
        }
    }

    /// An assumed settlement on a variable bill is the one case worth chasing:
    /// the amount matters and nobody knows it.
    public var needsAmountRecorded: Bool { isAssumed && isVariableAmount }

    public var id: String { "\(billID.uuidString)-\(dueDate.timeIntervalSince1970)" }
}

public struct MonthSummary: Hashable, Sendable {
    public let monthStart: Date
    public let occurrences: [BillOccurrence]

    /// Expected total for everything falling in the month.
    public var dueCents: Int { occurrences.reduce(0) { $0 + $1.expectedCents } }
    /// Amounts someone actually recorded. Can exceed the expectation on
    /// variable bills, which is the point of tracking it.
    public var recordedCents: Int { occurrences.reduce(0) { $0 + ($1.recordedCents ?? 0) } }
    /// Direct debits presumed to have gone out, valued at their expectation.
    /// Kept separate from `recordedCents` so a total is never presented as
    /// verified when it isn't.
    public var assumedCents: Int {
        occurrences.filter(\.isAssumed).reduce(0) { $0 + $1.expectedCents }
    }
    /// Everything considered settled, recorded or assumed.
    public var settledCents: Int { occurrences.reduce(0) { $0 + $1.settledCents } }
    public var outstandingCents: Int { occurrences.reduce(0) { $0 + $1.outstandingCents } }

    /// Variable bills that went out automatically with no amount recorded —
    /// exactly the figures that would otherwise be lost.
    public var needsAmountRecorded: [BillOccurrence] {
        occurrences.filter(\.needsAmountRecorded)
    }
}

/// A month in the forecast. The point is seeing the lumpy ones — rego,
/// insurance — before they arrive.
public struct ForecastMonth: Hashable, Sendable, Identifiable {
    public let monthStart: Date
    public let occurrences: [BillOccurrence]

    public var totalCents: Int { occurrences.reduce(0) { $0 + $1.expectedCents } }
    public var id: Date { monthStart }
}

/// One recorded payment, positioned for charting.
public struct TrendPoint: Hashable, Sendable, Identifiable {
    public let dueDate: Date
    public let amountCents: Int
    /// Far enough from the median to be worth a second look. Often it means the
    /// payment doesn't belong to this bill at all rather than that a real
    /// spike happened.
    public let isOutlier: Bool

    public var id: Date { dueDate }
}

/// Recorded payments for one bill over time, with the summary statistics needed
/// to read them.
///
/// Deliberately offers no fitted trendline. Utilities are seasonal — a rising
/// line through a Brisbane summer is aircon, not a price rise — and a regression
/// through a handful of points from one season would state the wrong conclusion
/// confidently. Answering "has it gone up" properly needs the same quarter a
/// year earlier, which needs a year of history.
public struct PaymentTrend: Hashable, Sendable {
    /// Oldest first, so the series reads left to right.
    public let points: [TrendPoint]
    public let medianCents: Int
    public let minCents: Int
    public let maxCents: Int

    /// Below this the history list says everything a chart would, and a
    /// two-point "trend" is a line between two numbers pretending to be
    /// information.
    public static let minimumPoints = 3
    /// Distance from the median, as a fraction, before a point is flagged.
    public static let outlierThreshold = 0.40

    public var isEmpty: Bool { points.isEmpty }
    public var isChartable: Bool { points.count >= Self.minimumPoints }
    public var latest: TrendPoint? { points.last }
    public var outliers: [TrendPoint] { points.filter(\.isOutlier) }
    /// Spread of recorded amounts — the honest one-line summary of a variable bill.
    public var rangeCents: Int { maxCents - minCents }
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
        now: Date? = nil,
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
                now: now ?? date,
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
        now: Date? = nil,
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
                    now: now ?? from,
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

    /// Average of the amounts actually recorded for a bill, or nil with no
    /// history.
    ///
    /// Shown *alongside* the estimate rather than replacing it: the monthly
    /// commitment is meant to be a stable "what do we spend" figure, and having
    /// it drift on its own as history accumulates would be surprising.
    public static func recordedAverageCents(billID: UUID, payments: [BillPaymentRecord]) -> Int? {
        let mine = payments.filter { $0.billID == billID }
        guard !mine.isEmpty else { return nil }
        let total = mine.reduce(0) { $0 + $1.amountCents }
        return Int((Double(total) / Double(mine.count)).rounded())
    }

    /// Recorded payments for one bill as a chartable series.
    ///
    /// Outliers are measured against the **median**, not the mean: with a
    /// handful of points one unusual payment drags a mean far enough to hide
    /// itself.
    public static func trend(billID: UUID, payments: [BillPaymentRecord]) -> PaymentTrend {
        let mine = payments
            .filter { $0.billID == billID }
            .sorted { $0.dueDate < $1.dueDate }

        guard !mine.isEmpty else {
            return PaymentTrend(points: [], medianCents: 0, minCents: 0, maxCents: 0)
        }

        let amounts = mine.map(\.amountCents)
        let median = medianCents(of: amounts)

        let points = mine.map { payment in
            TrendPoint(
                dueDate: payment.dueDate,
                amountCents: payment.amountCents,
                isOutlier: isOutlier(payment.amountCents, median: median)
            )
        }

        return PaymentTrend(
            points: points,
            medianCents: median,
            minCents: amounts.min() ?? 0,
            maxCents: amounts.max() ?? 0
        )
    }

    static func medianCents(of amounts: [Int]) -> Int {
        guard !amounts.isEmpty else { return 0 }
        let sorted = amounts.sorted()
        let middle = sorted.count / 2

        guard sorted.count % 2 == 0 else { return sorted[middle] }
        return Int((Double(sorted[middle - 1] + sorted[middle]) / 2).rounded())
    }

    static func isOutlier(_ amountCents: Int, median: Int) -> Bool {
        // Every amount is equally "normal" when there is nothing to compare to.
        guard median != 0 else { return false }
        let deviation = Double(abs(amountCents - median)) / Double(abs(median))
        return deviation > PaymentTrend.outlierThreshold
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
    ///
    /// `now` decides which automatic debits count as gone out; occurrences still
    /// in the future stay outstanding whether or not the bill pays itself.
    public static func occurrences(
        bills: [BillSpec],
        payments: [BillPaymentRecord],
        from: Date,
        to: Date,
        now: Date = Date(),
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

                        let settlement: BillOccurrence.Settlement
                        if let payment {
                            // A recorded amount always wins over an assumption.
                            settlement = .recorded(cents: payment.amountCents)
                        } else if bill.paysAutomatically, due <= now {
                            settlement = .assumed
                        } else {
                            settlement = .outstanding
                        }

                        return BillOccurrence(
                            billID: bill.id,
                            name: bill.name,
                            paidBy: bill.paidBy,
                            isVariableAmount: bill.isVariableAmount,
                            dueDate: due,
                            expectedCents: bill.amountCents,
                            settlement: settlement
                        )
                    }
            }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private static func active(_ bills: [BillSpec]) -> [BillSpec] {
        bills.filter(\.isActive)
    }
}
