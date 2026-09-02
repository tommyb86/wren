import XCTest
@testable import WrenCore

final class BillingPeriodTests: XCTestCase {

    private var brisbane: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Australia/Brisbane")!
        c.firstWeekday = 1
        return c
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        brisbane.date(from: DateComponents(year: year, month: month, day: day, hour: 9))!
    }

    private func schedule(_ frequency: Schedule.Frequency, interval: Int = 1, weekdays: Set<Int> = []) -> Schedule {
        Schedule(frequency: frequency, interval: interval, anchorDate: date(2026, 1, 1), weekdays: weekdays)
    }

    // MARK: - The worked example from the plan

    /// "A $120 quarterly bill is $40/month equivalent."
    func testQuarterlyBillNormalisesToAnExactTwelfth() {
        let quarterly = schedule(.monthly, interval: 3)

        XCTAssertEqual(BillingPeriod.monthlyEquivalentCents(amountCents: 12_000, schedule: quarterly), 4_000)
        XCTAssertEqual(BillingPeriod.annualCents(amountCents: 12_000, schedule: quarterly), 48_000)
    }

    // MARK: - Occurrences per year

    func testOccurrencesPerYearByFrequency() {
        XCTAssertEqual(BillingPeriod.occurrencesPerYear(schedule(.monthly)), 12, accuracy: 0.0001)
        XCTAssertEqual(BillingPeriod.occurrencesPerYear(schedule(.monthly, interval: 3)), 4, accuracy: 0.0001)
        XCTAssertEqual(BillingPeriod.occurrencesPerYear(schedule(.yearly)), 1, accuracy: 0.0001)
        XCTAssertEqual(BillingPeriod.occurrencesPerYear(schedule(.weekly)), 52.1775, accuracy: 0.0001)
        XCTAssertEqual(BillingPeriod.occurrencesPerYear(schedule(.weekly, interval: 2)), 26.08875, accuracy: 0.0001)
        XCTAssertEqual(BillingPeriod.occurrencesPerYear(schedule(.daily)), 365.2425, accuracy: 0.0001)
    }

    /// A weekly schedule listing three collection days bills three times a week.
    func testExplicitWeekdaysMultiplyTheRate() {
        let thriceWeekly = schedule(.weekly, weekdays: [2, 4, 6])

        XCTAssertEqual(
            BillingPeriod.occurrencesPerYear(thriceWeekly),
            52.1775 * 3,
            accuracy: 0.0001
        )
    }

    // MARK: - The fortnightly trap

    /// The mistake this exists to prevent: treating a fortnightly bill as
    /// two-per-month. There are 26.09 fortnights a year, not 24, so $50
    /// fortnightly is $108.70 a month rather than $100.
    func testFortnightlyIsNotSimplyTwicePerMonth() {
        let fortnightly = schedule(.weekly, interval: 2)
        let monthly = BillingPeriod.monthlyEquivalentCents(amountCents: 5_000, schedule: fortnightly)

        XCTAssertEqual(monthly, 10_870)
        XCTAssertNotEqual(monthly, 10_000, "fortnightly must not be treated as two payments a month")
        XCTAssertEqual(BillingPeriod.annualCents(amountCents: 5_000, schedule: fortnightly), 130_444)
    }

    func testWeeklyEquivalent() {
        // $120 quarterly over 52.1775 weeks.
        XCTAssertEqual(
            BillingPeriod.weeklyEquivalentCents(amountCents: 12_000, schedule: schedule(.monthly, interval: 3)),
            920
        )
    }

    // MARK: - Comparability

    /// The whole purpose: two bills at different cadences becoming comparable.
    func testDifferentCadencesBecomeComparable() {
        let quarterlyRates = BillingPeriod.monthlyEquivalentCents(
            amountCents: 45_000,
            schedule: schedule(.monthly, interval: 3)
        )
        let yearlyRego = BillingPeriod.monthlyEquivalentCents(
            amountCents: 90_000,
            schedule: schedule(.yearly)
        )
        let monthlyStreaming = BillingPeriod.monthlyEquivalentCents(
            amountCents: 1_599,
            schedule: schedule(.monthly)
        )

        XCTAssertEqual(quarterlyRates, 15_000) // $450/qtr -> $150/mo
        XCTAssertEqual(yearlyRego, 7_500)      // $900/yr  -> $75/mo
        XCTAssertEqual(monthlyStreaming, 1_599)

        XCTAssertTrue(quarterlyRates > yearlyRego, "rates cost more per month than rego")
    }

    // MARK: - Edge cases

    func testZeroAmountNormalisesToZero() {
        XCTAssertEqual(BillingPeriod.monthlyEquivalentCents(amountCents: 0, schedule: schedule(.monthly)), 0)
    }

    func testInvalidIntervalIsTreatedAsOne() {
        var broken = schedule(.monthly)
        broken.interval = 0

        XCTAssertEqual(BillingPeriod.occurrencesPerYear(broken), 12, accuracy: 0.0001)
    }

    /// Normalisation is a rate, so an end date must not change it — otherwise a
    /// bill's monthly-equivalent would drift as its end approached.
    func testEndDateDoesNotAffectNormalisation() {
        let open = schedule(.monthly, interval: 3)
        var closing = open
        closing.endDate = date(2026, 6, 30)

        XCTAssertEqual(
            BillingPeriod.monthlyEquivalentCents(amountCents: 12_000, schedule: open),
            BillingPeriod.monthlyEquivalentCents(amountCents: 12_000, schedule: closing)
        )
    }

    func testRoundingIsToTheNearestCent() {
        // $10 weekly: 52.1775 * 1000 / 12 = 4348.125 cents -> 4348.
        XCTAssertEqual(BillingPeriod.monthlyEquivalentCents(amountCents: 1_000, schedule: schedule(.weekly)), 4_348)
    }

    // MARK: - Descriptions

    func testCadenceDescriptions() {
        XCTAssertEqual(BillingPeriod.cadenceDescription(schedule(.monthly, interval: 3)), "quarterly")
        XCTAssertEqual(BillingPeriod.cadenceDescription(schedule(.weekly, interval: 2)), "fortnightly")
        XCTAssertEqual(BillingPeriod.cadenceDescription(schedule(.yearly)), "yearly")
        XCTAssertEqual(BillingPeriod.cadenceDescription(schedule(.monthly, interval: 6)), "twice a year")
        XCTAssertEqual(BillingPeriod.cadenceDescription(schedule(.monthly, interval: 4)), "every 4 months")
    }
}
