import XCTest
@testable import WrenCore

final class MoneyTests: XCTestCase {

    // MARK: - Parsing

    func testParsesWholeDollars() {
        XCTAssertEqual(Money.parse("120"), 12_000)
        XCTAssertEqual(Money.parse("0"), 0)
    }

    func testParsesDecimals() {
        XCTAssertEqual(Money.parse("120.50"), 12_050)
        XCTAssertEqual(Money.parse("0.05"), 5)
        XCTAssertEqual(Money.parse(".99"), 99)
    }

    /// "1.5" means a dollar fifty, not a dollar five.
    func testASingleDecimalDigitIsTens() {
        XCTAssertEqual(Money.parse("1.5"), 150)
        XCTAssertEqual(Money.parse("120.5"), 12_050)
    }

    func testStripsCurrencySymbolsAndSpaces() {
        XCTAssertEqual(Money.parse("$120.50"), 12_050)
        XCTAssertEqual(Money.parse(" $ 120.50 "), 12_050)
        XCTAssertEqual(Money.parse("AUD 120.50"), 12_050)
    }

    func testHandlesGroupingSeparators() {
        XCTAssertEqual(Money.parse("1,234.56"), 123_456)
        XCTAssertEqual(Money.parse("$1,234,567.89"), 123_456_789)
    }

    /// European style, where the roles of "." and "," are swapped.
    func testHandlesCommaAsDecimalSeparator() {
        XCTAssertEqual(Money.parse("1234,56"), 123_456)
        XCTAssertEqual(Money.parse("1.234,56"), 123_456)
    }

    func testTrailingSeparatorIsGroupingNotDecimal() {
        // Three digits after the separator cannot be cents.
        XCTAssertEqual(Money.parse("1,234"), 123_400)
    }

    func testParsesNegatives() {
        XCTAssertEqual(Money.parse("-12.40"), -1_240)
        XCTAssertEqual(Money.parse("-$12.40"), -1_240)
    }

    func testRejectsNonNumericInput() {
        XCTAssertNil(Money.parse(""))
        XCTAssertNil(Money.parse("abc"))
        XCTAssertNil(Money.parse("$"))
        XCTAssertNil(Money.parse("12-34"))
    }

    func testExtraFractionDigitsAreTruncated() {
        // Someone pasting a rate rather than an amount.
        XCTAssertEqual(Money.parse("12.3456"), 1_234)
    }

    // MARK: - Round-tripping

    func testParseSurvivesItsOwnOutput() {
        for cents in [0, 5, 99, 100, 12_050, 123_456_789, -1_240] {
            let text = Money.fallbackFormat(cents: cents, showsCents: true)
            XCTAssertEqual(Money.parse(text), cents, "round trip failed for \(cents)")
        }
    }

    // MARK: - Rounding

    func testRoundsToNearestDollar() {
        XCTAssertEqual(Money.roundToNearestDollar(12_049), 12_000)
        XCTAssertEqual(Money.roundToNearestDollar(12_050), 12_100)
        XCTAssertEqual(Money.roundToNearestDollar(12_099), 12_100)
        XCTAssertEqual(Money.roundToNearestDollar(0), 0)
    }

    func testRoundsNegativesAwayFromZeroAtTheHalf() {
        XCTAssertEqual(Money.roundToNearestDollar(-12_050), -12_100)
        XCTAssertEqual(Money.roundToNearestDollar(-12_049), -12_000)
    }

    // MARK: - Formatting

    /// Darwin and swift-corelibs disagree on currency formatting details, so the
    /// deterministic fallback is what gets asserted.
    func testFallbackFormatting() {
        XCTAssertEqual(Money.fallbackFormat(cents: 12_050, showsCents: true), "$120.50")
        XCTAssertEqual(Money.fallbackFormat(cents: 5, showsCents: true), "$0.05")
        XCTAssertEqual(Money.fallbackFormat(cents: 12_000, showsCents: false), "$120")
        XCTAssertEqual(Money.fallbackFormat(cents: -1_240, showsCents: true), "-$12.40")
    }

    func testFormatProducesSomethingContainingTheAmount() {
        // Locale-dependent, so this asserts only that the digits survive.
        let formatted = Money.format(cents: 12_050)
        XCTAssertTrue(formatted.contains("120"), "unexpected output: \(formatted)")
        XCTAssertTrue(formatted.contains("50"), "unexpected output: \(formatted)")
    }
}
