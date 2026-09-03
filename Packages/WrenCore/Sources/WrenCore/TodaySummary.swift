import Foundation

/// The one sentence at the top of Today.
///
/// Built from counts only, so it stays honest in every state — an empty week,
/// a backlog, ten bills — instead of needing hand-written copy for each
/// combination. The amount is returned separately so the UI can find it in the
/// text and highlight it.
public struct TodaySummary: Hashable, Sendable {
    public let text: String
    /// The formatted bill total, when the sentence mentions one.
    public let highlight: String?

    public init(text: String, highlight: String? = nil) {
        self.text = text
        self.highlight = highlight
    }

    public static func make(
        for agenda: TodayAgenda,
        hasAnythingSetUp: Bool = true,
        formatAmount: (Int) -> String = { Money.format(cents: $0) }
    ) -> TodaySummary {
        guard hasAnythingSetUp else {
            return TodaySummary(text: "Nothing set up yet.")
        }

        var sentences: [String] = []

        let overdue = agenda.overdue.filter(\.isActionable).count
        if overdue > 0 {
            sentences.append("\(count(overdue, "thing", "things").capitalisedFirst) \(overdue == 1 ? "needs" : "need") doing.")
        }

        // A bin due tomorrow morning is the one that goes out tonight; a bin due
        // today has already been collected by the time anyone reads this.
        let binsTonight = agenda.tomorrow.filter { $0.kind == .bin }.count
        let binsToday = agenda.today.filter { $0.kind == .bin }.count
        if binsTonight > 0 {
            sentences.append("\(count(binsTonight, "bin", "bins").capitalisedFirst) \(binsTonight == 1 ? "goes" : "go") out tonight.")
        } else if binsToday > 0 {
            sentences.append("\(count(binsToday, "bin", "bins").capitalisedFirst) collected today.")
        }

        let tasksToday = agenda.today.filter { $0.kind == .task }.count
        let tasksTomorrow = agenda.tomorrow.filter { $0.kind == .task }.count
        let taskClause: String?
        switch (tasksToday, tasksTomorrow) {
        case (0, 0):
            taskClause = nil
        case (let today, 0):
            taskClause = "\(count(today, "thing", "things")) to do today"
        case (0, let tomorrow):
            taskClause = "\(count(tomorrow, "thing", "things")) to do tomorrow"
        case (let today, let tomorrow):
            taskClause = "\(count(today, "thing", "things")) to do today and \(number(tomorrow)) tomorrow"
        }

        let billCents = (agenda.today + agenda.tomorrow + agenda.laterThisWeek)
            .filter { $0.kind == .bill }
            .compactMap(\.amountCents)
            .reduce(0, +)
        var highlight: String?
        var billClause: String?
        if billCents > 0 {
            let amount = formatAmount(billCents)
            highlight = amount
            billClause = "\(amount) in bills due this week"
        }

        switch (taskClause, billClause) {
        case (nil, nil):
            break
        case (let tasks?, nil):
            sentences.append("\(tasks.capitalisedFirst).")
        case (nil, let bills?):
            sentences.append("\(bills).")
        case (let tasks?, let bills?):
            sentences.append("\(tasks.capitalisedFirst), and \(bills).")
        }

        guard !sentences.isEmpty else {
            return TodaySummary(text: "Nothing on for the next week.")
        }
        return TodaySummary(text: sentences.joined(separator: " "), highlight: highlight)
    }

    // MARK: - Words

    static func count(_ n: Int, _ singular: String, _ plural: String) -> String {
        "\(number(n)) \(n == 1 ? singular : plural)"
    }

    /// Small counts read better as words in a sentence.
    static func number(_ n: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
        return n >= 0 && n < words.count ? words[n] : "\(n)"
    }
}

private extension String {
    var capitalisedFirst: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
