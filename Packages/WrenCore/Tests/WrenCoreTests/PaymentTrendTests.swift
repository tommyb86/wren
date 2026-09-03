import XCTest
@testable import WrenCore

final class PaymentTrendTests: XCTestCase {

    private var brisbane: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Australia/Brisbane")!
        c.firstWeekday = 1
        return c
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        brisbane.date(from: DateComponents(year: year, month: month, day: day, hour: 9))!
    }

    private let aglID = UUID()
    private let otherID = UUID()

    private func payment(_ cents: Int, _ month: Int, _ day: Int, bill: UUID? = nil) -> BillPaymentRecord {
        BillPaymentRecord(
            billID: bill ?? aglID,
            amountCents: cents,
            dueDate: date(2026, month, day),
            paidAt: date(2026, month, day)
        )
    }

    /// Real electricity history: five payments, one of them roughly half the
    /// others.
    private func aglHistory() -> [BillPaymentRecord] {
        [
            payment(18_522, 5, 7),
            payment(15_514, 6, 5),
            payment(16_262, 7, 7),
            payment(8_470, 7, 22),
            payment(15_828, 8, 5)
        ]
    }

    // MARK: - Median

    func testMedianOfAnOddCount() {
        XCTAssertEqual(BillReports.medianCents(of: [100, 300, 200]), 200)
    }

    func testMedianOfAnEvenCountAveragesTheMiddlePair() {
        XCTAssertEqual(BillReports.medianCents(of: [100, 200, 300, 400]), 250)
    }

    func testMedianRoundsToTheNearestCent() {
        XCTAssertEqual(BillReports.medianCents(of: [101, 102]), 102)
    }

    func testMedianOfNothingIsZero() {
        XCTAssertEqual(BillReports.medianCents(of: []), 0)
    }

    /// Why the median and not the mean. A single large payment drags a mean so
    /// far that the *ordinary* payments start looking anomalous — the failure is
    /// false positives on normal data, not a missed outlier.
    func testMeanWouldFalselyFlagOrdinaryPaymentsAroundOneSpike() {
        let amounts = [15_000, 15_500, 16_000, 90_000]
        let median = BillReports.medianCents(of: amounts)
        let mean = Int((Double(amounts.reduce(0, +)) / Double(amounts.count)).rounded())

        XCTAssertEqual(median, 15_750)
        XCTAssertEqual(mean, 34_125)

        // Against the median, only the spike stands out.
        XCTAssertTrue(BillReports.isOutlier(90_000, median: median))
        for ordinary in [15_000, 15_500, 16_000] {
            XCTAssertFalse(BillReports.isOutlier(ordinary, median: median), "\(ordinary) is unremarkable")
        }

        // Against the mean, every ordinary payment would be flagged.
        for ordinary in [15_000, 15_500, 16_000] {
            XCTAssertTrue(
                BillReports.isOutlier(ordinary, median: mean),
                "\(ordinary) would be a false positive against a mean of \(mean)"
            )
        }
    }

    /// On the real AGL history both statistics happen to catch the odd payment;
    /// the median just does so more decisively. Recorded so the claim above is
    /// not mistaken for "the mean always misses it".
    func testBothStatisticsCatchTheOddAGLPayment() {
        let amounts = aglHistory().map(\.amountCents)
        let median = BillReports.medianCents(of: amounts)
        let mean = Int((Double(amounts.reduce(0, +)) / Double(amounts.count)).rounded())

        XCTAssertEqual(median, 15_828)
        XCTAssertEqual(mean, 14_919)
        XCTAssertTrue(BillReports.isOutlier(8_470, median: median))
        XCTAssertTrue(BillReports.isOutlier(8_470, median: mean))
    }

    // MARK: - Outliers

    func testAPaymentWellBelowTheMedianIsFlagged() {
        let trend = BillReports.trend(billID: aglID, payments: aglHistory())

        XCTAssertEqual(trend.outliers.count, 1)
        XCTAssertEqual(trend.outliers.first?.amountCents, 8_470)
        XCTAssertEqual(trend.outliers.first?.dueDate, date(2026, 7, 22))
    }

    func testAPaymentWellAboveTheMedianIsAlsoFlagged() {
        var history = aglHistory()
        history.append(payment(40_000, 9, 5))

        let trend = BillReports.trend(billID: aglID, payments: history)

        XCTAssertTrue(trend.outliers.contains { $0.amountCents == 40_000 }, "spikes matter as much as dips")
    }

    func testOrdinaryVariationIsNotFlagged() {
        let steady = [payment(15_000, 5, 5), payment(16_000, 6, 5), payment(15_500, 7, 5)]

        XCTAssertTrue(BillReports.trend(billID: aglID, payments: steady).outliers.isEmpty)
    }

    func testTheThresholdBoundary() {
        // 40% is the threshold, and it is exclusive.
        XCTAssertFalse(BillReports.isOutlier(6_000, median: 10_000), "exactly 40% under is not yet an outlier")
        XCTAssertTrue(BillReports.isOutlier(5_999, median: 10_000))
        XCTAssertFalse(BillReports.isOutlier(14_000, median: 10_000))
        XCTAssertTrue(BillReports.isOutlier(14_001, median: 10_000))
    }

    func testNothingIsAnOutlierAgainstAZeroMedian() {
        XCTAssertFalse(BillReports.isOutlier(5_000, median: 0), "no basis for comparison")
    }

    // MARK: - Series

    func testPointsAreOldestFirst() {
        let trend = BillReports.trend(billID: aglID, payments: aglHistory().reversed())

        XCTAssertEqual(trend.points.map(\.dueDate), trend.points.map(\.dueDate).sorted())
        XCTAssertEqual(trend.latest?.dueDate, date(2026, 8, 5))
    }

    func testTrendIsScopedToOneBill() {
        var history = aglHistory()
        history.append(payment(99_999, 8, 6, bill: otherID))

        let trend = BillReports.trend(billID: aglID, payments: history)

        XCTAssertEqual(trend.points.count, 5)
        XCTAssertFalse(trend.points.contains { $0.amountCents == 99_999 })
    }

    func testRangeAndExtremes() {
        let trend = BillReports.trend(billID: aglID, payments: aglHistory())

        XCTAssertEqual(trend.minCents, 8_470)
        XCTAssertEqual(trend.maxCents, 18_522)
        XCTAssertEqual(trend.rangeCents, 10_052)
    }

    // MARK: - Chartability

    /// A two-point chart is a straight line between two numbers pretending to
    /// be information, so the history list stands in until there are three.
    func testFewerThanThreePaymentsIsNotChartable() {
        for count in 0...2 {
            let history = Array(aglHistory().prefix(count))
            let trend = BillReports.trend(billID: aglID, payments: history)
            XCTAssertFalse(trend.isChartable, "\(count) point(s) should not chart")
        }
    }

    func testThreePaymentsIsChartable() {
        let trend = BillReports.trend(billID: aglID, payments: Array(aglHistory().prefix(3)))

        XCTAssertTrue(trend.isChartable)
    }

    func testEmptyTrendIsSafeToRead() {
        let trend = BillReports.trend(billID: aglID, payments: [])

        XCTAssertTrue(trend.isEmpty)
        XCTAssertFalse(trend.isChartable)
        XCTAssertNil(trend.latest)
        XCTAssertEqual(trend.medianCents, 0)
        XCTAssertEqual(trend.rangeCents, 0)
    }
}
