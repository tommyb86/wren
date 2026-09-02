import XCTest
@testable import WrenCore

final class BillReportsTests: XCTestCase {

    private var brisbane: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Australia/Brisbane")!
        c.firstWeekday = 1
        return c
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
        brisbane.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private let electricityID = UUID()
    private let internetID = UUID()
    private let regoID = UUID()
    private let streamingID = UUID()

    /// A plausible household: quarterly power, monthly internet and streaming,
    /// yearly rego.
    private func household() -> [BillSpec] {
        [
            BillSpec(
                id: electricityID,
                name: "Electricity",
                amountCents: 45_000,
                isVariableAmount: true,
                schedule: Schedule(frequency: .monthly, interval: 3, anchorDate: date(2026, 1, 15)),
                category: "Utilities"
            ),
            BillSpec(
                id: internetID,
                name: "Internet",
                amountCents: 8_900,
                schedule: Schedule(frequency: .monthly, anchorDate: date(2026, 1, 5)),
                category: "Utilities"
            ),
            BillSpec(
                id: regoID,
                name: "Car rego",
                amountCents: 90_000,
                schedule: Schedule(frequency: .yearly, anchorDate: date(2026, 3, 20)),
                category: "Car"
            ),
            BillSpec(
                id: streamingID,
                name: "Streaming",
                amountCents: 1_599,
                schedule: Schedule(frequency: .monthly, anchorDate: date(2026, 1, 8)),
                category: "Subscriptions"
            )
        ]
    }

    // MARK: - Headline figures

    func testMonthlyCommitmentSumsNormalisedAmounts() {
        // 15000 (power) + 8900 (internet) + 7500 (rego) + 1599 (streaming)
        XCTAssertEqual(BillReports.monthlyCommitmentCents(household()), 32_999)
    }

    func testAnnualCommitment() {
        // 180000 + 106800 + 90000 + 19188
        XCTAssertEqual(BillReports.annualCommitmentCents(household()), 395_988)
    }

    func testInactiveBillsAreExcludedFromCommitment() {
        var bills = household()
        bills[0] = BillSpec(
            id: electricityID,
            name: "Electricity",
            amountCents: 45_000,
            schedule: bills[0].schedule,
            category: "Utilities",
            isActive: false
        )

        XCTAssertEqual(BillReports.monthlyCommitmentCents(bills), 32_999 - 15_000)
    }

    func testEmptyBillsGiveZero() {
        XCTAssertEqual(BillReports.monthlyCommitmentCents([]), 0)
        XCTAssertEqual(BillReports.annualCommitmentCents([]), 0)
    }

    // MARK: - By category

    func testByCategoryGroupsAndSortsLargestFirst() {
        let totals = BillReports.byCategory(household())

        XCTAssertEqual(totals.map(\.category), ["Utilities", "Car", "Subscriptions"])
        XCTAssertEqual(totals[0].monthlyCents, 15_000 + 8_900)
        XCTAssertEqual(totals[0].billCount, 2)
        XCTAssertEqual(totals[1].monthlyCents, 7_500)
        XCTAssertEqual(totals[2].monthlyCents, 1_599)
    }

    func testUncategorisedBillsGetAnExplicitLabel() {
        let bills = [
            BillSpec(
                id: UUID(),
                name: "Something",
                amountCents: 1_000,
                schedule: Schedule(frequency: .monthly, anchorDate: date(2026, 1, 1)),
                category: "   "
            )
        ]

        XCTAssertEqual(BillReports.byCategory(bills).map(\.category), ["Uncategorised"])
    }

    func testCategoryTotalsSumToTheOverallCommitment() {
        let totals = BillReports.byCategory(household())

        XCTAssertEqual(
            totals.reduce(0) { $0 + $1.monthlyCents },
            BillReports.monthlyCommitmentCents(household())
        )
    }

    // MARK: - This month

    func testMonthSummarySplitsPaidFromOutstanding() {
        // January 2026: internet (5th), streaming (8th), electricity (15th).
        let payments = [
            BillPaymentRecord(billID: internetID, amountCents: 8_900, dueDate: date(2026, 1, 5), paidAt: date(2026, 1, 5))
        ]

        let summary = BillReports.monthSummary(
            bills: household(),
            payments: payments,
            containing: date(2026, 1, 20),
            calendar: brisbane
        )

        XCTAssertEqual(summary.monthStart, date(2026, 1, 1, 0))
        XCTAssertEqual(summary.occurrences.count, 3)
        XCTAssertEqual(summary.dueCents, 8_900 + 1_599 + 45_000)
        XCTAssertEqual(summary.paidCents, 8_900)
        XCTAssertEqual(summary.outstandingCents, 1_599 + 45_000)
    }

    func testMonthSummaryOccurrencesAreDateOrdered() {
        let summary = BillReports.monthSummary(
            bills: household(),
            payments: [],
            containing: date(2026, 1, 20),
            calendar: brisbane
        )

        XCTAssertEqual(summary.occurrences.map(\.dueDate), summary.occurrences.map(\.dueDate).sorted())
        XCTAssertEqual(summary.occurrences.first?.name, "Internet")
    }

    /// A payment recorded at a different time of day on the right date still
    /// settles that occurrence.
    func testPaymentMatchingIsAtDayGranularity() {
        let payments = [
            BillPaymentRecord(
                billID: internetID,
                amountCents: 8_900,
                dueDate: date(2026, 1, 5, 22),
                paidAt: date(2026, 1, 5, 22)
            )
        ]

        let summary = BillReports.monthSummary(
            bills: household(),
            payments: payments,
            containing: date(2026, 1, 20),
            calendar: brisbane
        )

        XCTAssertTrue(
            summary.occurrences.first { $0.billID == self.internetID }?.isPaid ?? false,
            "history must survive a due-time edit"
        )
    }

    // MARK: - Forecast

    func testForecastCoversTwelveMonthsFromTheContainingMonth() {
        let forecast = BillReports.forecast(
            bills: household(),
            from: date(2026, 1, 20),
            months: 12,
            calendar: brisbane
        )

        XCTAssertEqual(forecast.count, 12)
        XCTAssertEqual(forecast.first?.monthStart, date(2026, 1, 1, 0))
        XCTAssertEqual(forecast.last?.monthStart, date(2026, 12, 1, 0))
    }

    /// The point of the forecast: seeing that March is expensive because rego
    /// lands, before March arrives.
    func testForecastExposesLumpyMonths() {
        let forecast = BillReports.forecast(
            bills: household(),
            from: date(2026, 1, 1),
            months: 12,
            calendar: brisbane
        )

        let march = forecast.first { brisbane.component(.month, from: $0.monthStart) == 3 }
        let february = forecast.first { brisbane.component(.month, from: $0.monthStart) == 2 }

        // March: internet + streaming + rego. February: internet + streaming.
        XCTAssertEqual(february?.totalCents, 8_900 + 1_599)
        XCTAssertEqual(march?.totalCents, 8_900 + 1_599 + 90_000)
        XCTAssertTrue((march?.totalCents ?? 0) > BillReports.averageMonthlyCents(forecast))
    }

    func testForecastTotalApproximatesTheAnnualCommitment() {
        let forecast = BillReports.forecast(
            bills: household(),
            from: date(2026, 1, 1),
            months: 12,
            calendar: brisbane
        )
        let forecastTotal = forecast.reduce(0) { $0 + $1.totalCents }

        // Dated occurrences and the normalised rate should agree closely; they
        // differ only because a calendar year doesn't hold a whole number of
        // fortnights and this household has none.
        XCTAssertEqual(forecastTotal, BillReports.annualCommitmentCents(household()))
    }

    func testForecastRespectsAnEndDate() {
        let ending = [
            BillSpec(
                id: streamingID,
                name: "Streaming",
                amountCents: 1_599,
                schedule: Schedule(
                    frequency: .monthly,
                    anchorDate: date(2026, 1, 8),
                    endDate: date(2026, 3, 31)
                ),
                category: "Subscriptions"
            )
        ]

        let forecast = BillReports.forecast(bills: ending, from: date(2026, 1, 1), months: 12, calendar: brisbane)

        XCTAssertEqual(forecast.filter { $0.totalCents > 0 }.count, 3, "a cancelled subscription must stop costing")
    }

    func testZeroMonthsForecastIsEmpty() {
        XCTAssertTrue(BillReports.forecast(bills: household(), from: date(2026, 1, 1), months: 0).isEmpty)
    }

    func testAverageOfAnEmptyForecastIsZero() {
        XCTAssertEqual(BillReports.averageMonthlyCents([]), 0)
    }

    // MARK: - History

    func testHistoryIsNewestFirstAndScopedToOneBill() {
        let payments = [
            BillPaymentRecord(billID: electricityID, amountCents: 41_000, dueDate: date(2026, 1, 15), paidAt: date(2026, 1, 16)),
            BillPaymentRecord(billID: electricityID, amountCents: 52_000, dueDate: date(2026, 4, 15), paidAt: date(2026, 4, 15)),
            BillPaymentRecord(billID: internetID, amountCents: 8_900, dueDate: date(2026, 1, 5), paidAt: date(2026, 1, 5))
        ]

        let history = BillReports.history(billID: electricityID, payments: payments)

        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history.map(\.amountCents), [52_000, 41_000])
    }

    // MARK: - Variance

    /// The interesting signal on a variable bill: the power bill went up.
    func testVarianceComparesActualAgainstExpectedPerPayment() {
        let payments = [
            BillPaymentRecord(billID: electricityID, amountCents: 41_000, dueDate: date(2026, 1, 15), paidAt: date(2026, 1, 16)),
            BillPaymentRecord(billID: electricityID, amountCents: 52_000, dueDate: date(2026, 4, 15), paidAt: date(2026, 4, 15))
        ]

        let variance = BillReports.variance(bill: household()[0], payments: payments)

        XCTAssertEqual(variance.paymentCount, 2)
        XCTAssertEqual(variance.expectedCents, 90_000) // 2 x $450 estimate
        XCTAssertEqual(variance.actualCents, 93_000)
        XCTAssertEqual(variance.differenceCents, 3_000)
        XCTAssertEqual(variance.percentDifference ?? 0, 3.333, accuracy: 0.01)
    }

    func testVarianceIsNegativeWhenUnderBudget() {
        let payments = [
            BillPaymentRecord(billID: internetID, amountCents: 7_900, dueDate: date(2026, 1, 5), paidAt: date(2026, 1, 5))
        ]

        let variance = BillReports.variance(bill: household()[1], payments: payments)

        XCTAssertEqual(variance.differenceCents, -1_000)
    }

    func testVarianceWithNoPaymentsIsZeroed() {
        let variance = BillReports.variance(bill: household()[0], payments: [])

        XCTAssertEqual(variance.paymentCount, 0)
        XCTAssertEqual(variance.expectedCents, 0)
        XCTAssertEqual(variance.differenceCents, 0)
        XCTAssertNil(variance.percentDifference, "no expectation means no percentage")
    }

    func testVariancesListsWorstOverspendFirstAndSkipsUnpaidBills() {
        let payments = [
            BillPaymentRecord(billID: electricityID, amountCents: 52_000, dueDate: date(2026, 1, 15), paidAt: date(2026, 1, 15)),
            BillPaymentRecord(billID: internetID, amountCents: 7_900, dueDate: date(2026, 1, 5), paidAt: date(2026, 1, 5))
        ]

        let variances = BillReports.variances(bills: household(), payments: payments)

        XCTAssertEqual(variances.count, 2, "bills with no payments have nothing to compare")
        XCTAssertEqual(variances.first?.billID, electricityID)
        XCTAssertEqual(variances.first?.differenceCents, 7_000)
        XCTAssertEqual(variances.last?.differenceCents, -1_000)
    }
}
