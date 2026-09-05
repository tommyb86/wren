import XCTest
@testable import WrenCore

final class SchoolTests: XCTestCase {

    // MARK: - HTML flattening

    func testPlainStripsTagsAndDecodesEntities() {
        let html = "<p>Please note there will be parking on P&amp;F Oval from <strong>1.00pm</strong>.</p>"
        XCTAssertEqual(
            SchoolText.plain(fromHTML: html),
            "Please note there will be parking on P&F Oval from 1.00pm."
        )
    }

    func testPlainDecodesNumericEntity() {
        XCTAssertEqual(SchoolText.plain(fromHTML: "Father&#8217;s Day"), "Father\u{2019}s Day")
    }

    func testFirstImageHash() {
        let html = "<a href=\"/storage/image.php?hash=b7d902d6\"><img src=\"/storage/image.php?hash=b7d902d6\"></a>"
        XCTAssertEqual(SchoolText.firstImageHash(inHTML: html), "b7d902d6")
    }

    // MARK: - RSS parsing

    private let sampleRSS = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss version="2.0">
      <channel>
        <title>Example School News</title>
        <item>
          <title>Reminder: Father&#039;s Day Assembly</title>
          <category></category>
          <description><![CDATA[<p>Parking on <strong>P&amp;F Oval</strong> from 1.00pm.</p>]]></description>
          <link>https://school.example/news/31326?ref=rss</link>
          <pubDate>Fri, 04 Sep 2026 14:01:00 +1000</pubDate>
          <guid>https://school.example/news/31326</guid>
        </item>
        <item>
          <title>Week 9 Week B</title>
          <description><![CDATA[<p>Assessment week.</p>]]></description>
          <pubDate>Fri, 04 Sep 2026 15:31:00 +1000</pubDate>
          <guid>https://school.example/news/31287</guid>
        </item>
      </channel>
    </rss>
    """

    func testParserExtractsItems() {
        let items = SchoolFeedParser.parse(sampleRSS)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].guid, "31326")
        XCTAssertEqual(items[0].title, "Reminder: Father's Day Assembly")
        XCTAssertEqual(items[0].bodyText, "Parking on P&F Oval from 1.00pm.")
        XCTAssertEqual(items[0].position, 0)
        XCTAssertTrue(items[0].isPinned)
        XCTAssertNotNil(items[0].published)
    }

    func testParsedGuidIsNumericId() {
        let items = SchoolFeedParser.parse(sampleRSS)
        XCTAssertEqual(items[1].guid, "31287")
    }

    func testParserKeepsBodyHTML() {
        let items = SchoolFeedParser.parse(sampleRSS)
        XCTAssertTrue(items[0].bodyHTML.contains("<strong>"))
    }

    // MARK: - Structured body

    func testBodyBlocksSplitParagraphsAndBullets() {
        let html = "<p>Week 8 was busy.</p><p>Uniform reminder:</p><ul><li>Blazers compulsory</li><li>Hair above the collar</li></ul>"
        let blocks = SchoolBody.blocks(fromHTML: html)
        XCTAssertEqual(blocks.count, 4)
        XCTAssertEqual(blocks[0], .paragraph("Week 8 was busy."))
        XCTAssertEqual(blocks[1], .paragraph("Uniform reminder:"))
        XCTAssertEqual(blocks[2], .bullet("Blazers compulsory"))
        XCTAssertTrue(blocks[3].isBullet)
    }

    func testBodyBlocksFallBackToPlainWhenNoMarkup() {
        let blocks = SchoolBody.blocks(fromHTML: "Just a line with no tags.")
        XCTAssertEqual(blocks, [.paragraph("Just a line with no tags.")])
    }

    // MARK: - Series

    func testSeriesStem() {
        XCTAssertEqual(
            SchoolSeries.stem(of: "Birtles House Charity - Watoto - Day 12"),
            "Birtles House Charity - Watoto"
        )
        XCTAssertEqual(SchoolSeries.stem(of: "Advent Reflections – Part 3"), "Advent Reflections")
    }

    func testNonSeriesTitlesReturnNil() {
        XCTAssertNil(SchoolSeries.stem(of: "Week 9 Week B"))
        XCTAssertNil(SchoolSeries.stem(of: "GPS Student & Family Survey"))
        XCTAssertNil(SchoolSeries.stem(of: "Churchie Round this weekend"))
    }

    func testGroupCollapsesSeries() {
        let items = (1...5).map {
            SchoolFeedItem(guid: "g\($0)", title: "Watoto - Day \($0)", bodyText: "", published: nil, position: $0)
        } + [SchoolFeedItem(guid: "x", title: "College Shop notice", bodyText: "", published: nil, position: 9)]
        let groups = SchoolSeries.group(items)
        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(groups[0].isSeries)
        XCTAssertEqual(groups[0].count, 5)
        XCTAssertFalse(groups[1].isSeries)
    }

    // MARK: - Relevance

    private func item(_ title: String, _ body: String = "", labels: [String] = []) -> SchoolFeedItem {
        SchoolFeedItem(guid: UUID().uuidString, title: title, bodyText: body, published: nil, labels: labels)
    }

    private let year4 = SchoolProfile(yearLevel: 4, house: "Rowan", activities: ["Football", "Pipe Band"])

    func testProvenanceWins() {
        let m = SchoolRelevance.match(item("Week 9 Week B", labels: ["Year 4 Community"]), profile: year4)
        XCTAssertEqual(m.bucket, .forMe)
        XCTAssertEqual(m.tags.first?.label, "Year 4 Community")
        XCTAssertTrue(m.tags.first?.isSchoolLabel ?? false)
    }

    func testYearRangeMatchesLowerBound() {
        // The case naive substring matching gets wrong.
        let m = SchoolRelevance.match(
            item("GPS Debating registration", "Open to all current Year 4 to Year 11 students."),
            profile: year4
        )
        XCTAssertEqual(m.bucket, .forMe)
        XCTAssertEqual(m.tags.first?.label, "Year 4")
        XCTAssertFalse(m.tags.first?.isSchoolLabel ?? true)
    }

    func testActivityMatch() {
        let m = SchoolRelevance.match(item("Order Football group photo", "Football teams."), profile: year4)
        XCTAssertEqual(m.bucket, .forMe)
        XCTAssertTrue(m.tags.contains { $0.label == "Football" })
    }

    func testJuniorSectionMatch() {
        let m = SchoolRelevance.match(item("Junior School Father's Day Assembly", "All welcome."), profile: year4)
        XCTAssertEqual(m.bucket, .forMe)
    }

    func testAlwaysShowUniform() {
        let m = SchoolRelevance.match(item("Churchie Round", "You will not be required to bring your blazers."), profile: year4)
        XCTAssertEqual(m.bucket, .wholeSchool)
        XCTAssertTrue(m.tags.contains { $0.label == "Uniform" })
    }

    func testUnmatchedFallsToEverythingElse() {
        let m = SchoolRelevance.match(item("Class of 1976 — 50 Year Reunion", "Old boys welcome."), profile: year4)
        XCTAssertEqual(m.bucket, .everythingElse)
        XCTAssertTrue(SchoolRelevance.isNegative(item("Class of 1976 — 50 Year Reunion", "Old boys welcome.")))
    }

    func testUnconfiguredProfileMatchesNothingByYear() {
        let m = SchoolRelevance.match(item("Year 4 excursion", "Year 4 only."), profile: SchoolProfile())
        XCTAssertEqual(m.bucket, .everythingElse)
    }

    // MARK: - Deadlines

    private var brisbane: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Australia/Brisbane")!
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        brisbane.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    func testExtractsFullDateWithYear() {
        let blocks = ["Survey Closing Date Thursday 24 September 2026. Please respond."]
        let published = day(2026, 9, 2)
        let found = SchoolDeadlines.extract(fromBlocks: blocks, published: published, calendar: brisbane)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(brisbane.startOfDay(for: found[0].date), brisbane.startOfDay(for: day(2026, 9, 24)))
        XCTAssertEqual(found[0].confidence, .high)
    }

    func testInfersYearForBareDate() {
        // Posted in November; "5 February" should resolve to the next February.
        let blocks = ["Please register by 5 February for the season."]
        let found = SchoolDeadlines.extract(fromBlocks: blocks, published: day(2026, 11, 10), calendar: brisbane)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(brisbane.component(.year, from: found[0].date), 2027)
        XCTAssertEqual(found[0].confidence, .medium)
    }

    func testDateWithoutCueIsIgnored() {
        let blocks = ["We had a lovely time on 12 August at the fair."]
        let found = SchoolDeadlines.extract(fromBlocks: blocks, published: day(2026, 8, 20), calendar: brisbane)
        XCTAssertTrue(found.isEmpty)
    }

    func testExtractFromHTMLUsesBlocks() {
        let html = "<p>Curriculum notes.</p><p>Ordering closes 30 September 2026.</p>"
        let found = SchoolDeadlines.extract(fromHTML: html, published: day(2026, 9, 1), calendar: brisbane)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(brisbane.startOfDay(for: found[0].date), brisbane.startOfDay(for: day(2026, 9, 30)))
        XCTAssertTrue(found[0].evidence.contains("Ordering closes"))
    }
}
