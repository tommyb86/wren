import XCTest
@testable import WrenCore

final class ReceiptParserTests: XCTestCase {

    private var brisbane: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Australia/Brisbane")!
        c.firstWeekday = 1
        return c
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        brisbane.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private var now: Date { date(2026, 9, 3) }

    private func parse(_ text: String) -> ReceiptSuggestions {
        ReceiptParser.parse(text, now: now, calendar: brisbane)
    }

    /// A realistic Australian grocery docket, including the noise that trips
    /// naive parsers: an ABN, a phone number, a subtotal, GST, and change.
    private let woolworths = """
    WOOLWORTHS
    CHERMSIDE QLD 4032
    ABN 88 000 014 675
    PH 07 3359 1111
    TAX INVOICE

    MILK 2L            3.10
    BREAD MULTIGRAIN   4.50
    BANANAS 1.2KG      5.28
    CHICKEN THIGH     12.90

    SUBTOTAL          25.78
    GST                2.34
    TOTAL             25.78
    CASH              50.00
    CHANGE            24.22

    03/09/2026 14:32
    THANK YOU FOR SHOPPING
    """

    // MARK: - The whole thing

    func testParsesARealisticDocket() {
        let result = parse(woolworths)

        XCTAssertEqual(result.vendor, "WOOLWORTHS")
        XCTAssertEqual(result.totalCents, 2_578)
        XCTAssertEqual(result.date, date(2026, 9, 3))
        XCTAssertFalse(result.isEmpty)
    }

    func testEmptyTextYieldsNothingRatherThanGuessing() {
        let result = parse("")

        XCTAssertTrue(result.isEmpty)
        XCTAssertTrue(result.candidateTotals.isEmpty)
        XCTAssertTrue(result.candidateDates.isEmpty)
    }

    // MARK: - Totals

    func testTheTotalLineBeatsTheLargestAmount() {
        // CASH 50.00 is the biggest number on the docket; TOTAL is what matters.
        XCTAssertEqual(parse(woolworths).totalCents, 2_578)
    }

    func testSubtotalAndGstAreOutrankedByTheTotal() {
        let text = """
        SUBTOTAL   90.00
        GST         9.00
        TOTAL      99.00
        """

        XCTAssertEqual(parse(text).totalCents, 9_900)
    }

    func testAmountDueIsRecognised() {
        let text = """
        BRISBANE CITY COUNCIL
        AMOUNT DUE   796.45
        """

        XCTAssertEqual(parse(text).totalCents, 79_645)
    }

    /// With no keyword to go on, the biggest amount is the best available guess.
    func testFallsBackToTheLargestAmount() {
        let text = """
        CORNER STORE
        COFFEE   4.50
        MUFFIN   5.00
        9.50
        """

        XCTAssertEqual(parse(text).totalCents, 950)
    }

    /// A mangled total line must not leave the user with nothing to choose
    /// from, so every amount stays a candidate — only the order changes.
    func testEveryAmountRemainsSelectable() {
        let candidates = parse(woolworths).candidateTotals

        XCTAssertEqual(candidates.first, 2_578)
        for amount in [310, 450, 528, 1_290, 5_000, 2_422, 234] {
            XCTAssertTrue(candidates.contains(amount), "\(amount) should still be pickable")
        }
    }

    func testCandidatesAreDeduplicated() {
        // SUBTOTAL and TOTAL are both 25.78 on this docket.
        let candidates = parse(woolworths).candidateTotals

        XCTAssertEqual(candidates.filter { $0 == 2_578 }.count, 1)
    }

    func testAmountsRequireCentsSoIdentifiersAreIgnored() {
        let text = """
        SOME SHOP
        ABN 88 000 014 675
        PH 07 3359 1111
        LOYALTY POINTS 1250
        TOTAL 42.00
        """

        XCTAssertEqual(parse(text).totalCents, 4_200)
        XCTAssertEqual(parse(text).candidateTotals, [4_200], "bare integers are not amounts")
    }

    func testHandlesThousandsSeparatorsAndDollarSigns() {
        let text = """
        MYCAR CHERMSIDE
        TOTAL   $1,492.00
        """

        XCTAssertEqual(parse(text).totalCents, 149_200)
    }

    // MARK: - Dates

    /// Australia is day-first. Reading 03/09/2026 as 9 March would file the
    /// receipt in the wrong financial year.
    func testNumericDatesAreDayFirst() {
        XCTAssertEqual(parse("TOTAL 5.00\n03/09/2026").date, date(2026, 9, 3))
    }

    func testAcceptsDashAndDotSeparators() {
        XCTAssertEqual(parse("TOTAL 5.00\n03-09-2026").date, date(2026, 9, 3))
        XCTAssertEqual(parse("TOTAL 5.00\n01.08.2026").date, date(2026, 8, 1))
    }

    func testTwoDigitYearsAreThisCentury() {
        XCTAssertEqual(parse("TOTAL 5.00\n03/09/26").date, date(2026, 9, 3))
    }

    func testParsesWrittenDatesBothWaysRound() {
        XCTAssertEqual(parse("TOTAL 5.00\n3 Sep 2026").date, date(2026, 9, 3))
        XCTAssertEqual(parse("TOTAL 5.00\n3 September 2026").date, date(2026, 9, 3))
        XCTAssertEqual(parse("TOTAL 5.00\nSep 3, 2026").date, date(2026, 9, 3))
    }

    /// Card expiry and "valid until" dates are in the future; the purchase
    /// never is.
    func testFutureDatesAreRejected() {
        let text = """
        SOME SHOP
        TOTAL 5.00
        CARD EXPIRY 05/2030
        01/09/2026
        """

        XCTAssertEqual(parse(text).date, date(2026, 9, 1))
        XCTAssertFalse(parse(text).candidateDates.contains { $0 > self.now })
    }

    func testTheMostRecentPlausibleDateWins() {
        let text = """
        SOME SHOP
        ABN REGISTERED 12/03/2011
        TOTAL 5.00
        02/09/2026
        """

        XCTAssertEqual(parse(text).date, date(2026, 9, 2))
    }

    func testImpossibleDatesAreRejected() {
        XCTAssertNil(parse("TOTAL 5.00\n32/01/2026").date)
        XCTAssertNil(parse("TOTAL 5.00\n01/13/2026").date)
        XCTAssertNil(parse("TOTAL 5.00\n31/02/2026").date, "February has no 31st, and must not roll into March")
    }

    func testAncientDatesAreRejected() {
        XCTAssertNil(parse("TOTAL 5.00\n01/01/2005").date, "beyond the 15-year floor")
    }

    // MARK: - Vendor

    func testVendorIsTheFirstRealNameLine() {
        XCTAssertEqual(parse(woolworths).vendor, "WOOLWORTHS")
    }

    func testVendorSkipsHeaderNoise() {
        let text = """
        TAX INVOICE
        CUSTOMER COPY
        BUNNINGS WAREHOUSE
        VIRGINIA QLD
        TOTAL 166.55
        """

        XCTAssertEqual(parse(text).vendor, "BUNNINGS WAREHOUSE")
    }

    func testVendorSkipsLinesThatAreMostlyDigits() {
        let text = """
        07 3359 1111
        ABN 88 000 014 675
        THE STANDARD MARKET
        TOTAL 9.66
        """

        XCTAssertEqual(parse(text).vendor, "THE STANDARD MARKET")
    }

    func testVendorSkipsLinesCarryingAnAmount() {
        let text = """
        MILK 2L 3.10
        JEROBOAM GROUP
        TOTAL 22.39
        """

        XCTAssertEqual(parse(text).vendor, "JEROBOAM GROUP")
    }

    func testVendorCollapsesOcrWhitespace() {
        XCTAssertEqual(parse("SUSHI    HONTEN\nTOTAL 13.77").vendor, "SUSHI HONTEN")
    }

    func testVendorIsNilWhenThereIsNoNameToFind() {
        XCTAssertNil(parse("TAX INVOICE\n07 3359 1111\nTOTAL 5.00").vendor)
    }

    /// The vendor is only looked for near the top; a trailing "THANK YOU FOR
    /// SHOPPING AT ..." shouldn't win over the header.
    func testOnlyTheTopOfTheReceiptIsSearchedForAVendor() {
        let text = """
        1
        2
        3
        4
        5
        6
        COLES SUPERMARKET
        """

        XCTAssertNil(parse(text).vendor)
    }

    // MARK: - Financial year integration

    /// The practical payoff: a receipt from late June files into the closing
    /// financial year, not the new one.
    func testAJuneReceiptFilesIntoTheClosingFinancialYear() {
        let result = ReceiptParser.parse(
            "OFFICEWORKS\nTOTAL 249.00\n28/06/2026",
            now: date(2026, 7, 5),
            calendar: brisbane
        )

        let parsed = try? XCTUnwrap(result.date)
        XCTAssertEqual(parsed, date(2026, 6, 28))
        XCTAssertEqual(FinancialYear.containing(parsed!, calendar: brisbane).startYear, 2025)
    }
}
