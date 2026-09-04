import SwiftUI
import SwiftData
import WrenCore

/// The reporting set from the plan. Bills exist to answer "what does this
/// household cost", so this screen is the payoff rather than an extra.
@MainActor
struct ReportsView: View {
    @Query(sort: \Bill.sortOrder) private var bills: [Bill]

    @State private var selectedForecastMonth: ForecastMonth?
    @State private var exportText: String?

    private let calendar = Calendar.current

    private var specs: [BillSpec] { bills.compactMap(\.spec) }
    private var payments: [BillPaymentRecord] { bills.flatMap(\.paymentRecords) }

    private var forecast: [ForecastMonth] {
        BillReports.forecast(bills: specs, payments: payments, from: Date(), months: 12, calendar: calendar)
    }

    var body: some View {
        List {
            if specs.isEmpty {
                Section {
                    Text("Add a bill and the reports fill in.")
                        .font(.subheadline)
                        .foregroundStyle(Color.wren.textSecondary)
                        .padding(.vertical, Space.xs)
                        .wrenRow(first: true, last: true)
                }
            } else {
                commitmentSection
                thisMonthSection
                forecastSection
                categorySection
                varianceSection
                exportSection
            }
        }
        .wrenListStyle()
        .navigationTitle("Reports")
        .sheet(item: Binding(
            get: { exportText.map(ExportPayload.init) },
            set: { exportText = $0?.text }
        )) { payload in
            ShareSheet(text: payload.text)
        }
    }

    // MARK: - Headline

    private var commitmentSection: some View {
        let stats = [
            ("Annual", Money.format(cents: BillReports.annualCommitmentCents(specs))),
            ("Weekly", Money.format(cents: weeklyCents))
        ]

        return Section {
            VStack(alignment: .leading, spacing: 2) {
                Text(Money.format(cents: BillReports.monthlyCommitmentCents(specs)))
                    .font(WrenFont.title)
                    .monospacedDigit()
                    .foregroundStyle(Color.wren.textPrimary)
                Text("a month")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.wren.textSecondary)
            }
            .padding(.vertical, Space.xs)
            .wrenRow(first: true)

            ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                WrenStatRow(label: stat.0, value: stat.1)
                    .wrenRow(last: index == stats.count - 1)
            }
        } header: {
            WrenListHeader(text: "Monthly commitment")
        } footer: {
            WrenListFooter(text: "Every bill converted to a monthly equivalent. A quarterly bill counts as a third of itself each month, so this is what the household costs on average — not what lands this month.")
        }
    }

    private var weeklyCents: Int {
        specs.filter(\.isActive).reduce(0) {
            $0 + BillingPeriod.weeklyEquivalentCents(amountCents: $1.amountCents, schedule: $1.schedule)
        }
    }

    // MARK: - This month

    private var thisMonthSection: some View {
        let summary = BillReports.monthSummary(
            bills: specs,
            payments: payments,
            containing: Date(),
            calendar: calendar
        )

        var stats: [(String, String, Bool)] = [
            ("Due", Money.format(cents: summary.dueCents), false),
            ("Recorded", Money.format(cents: summary.recordedCents), false)
        ]
        // Never folded into "Recorded": an assumed direct debit is not a
        // verified figure, and presenting it as one would be a lie.
        if summary.assumedCents > 0 {
            stats.append(("Assumed paid", Money.format(cents: summary.assumedCents), false))
        }
        stats.append(("Outstanding", Money.format(cents: summary.outstandingCents), true))

        return Section {
            ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                WrenStatRow(label: stat.0, value: stat.1, emphasised: stat.2)
                    .wrenRow(first: index == 0, last: summary.occurrences.isEmpty && index == stats.count - 1)
            }

            ForEach(Array(summary.occurrences.enumerated()), id: \.element.id) { index, occurrence in
                occurrenceRow(occurrence)
                    .wrenRow(last: index == summary.occurrences.count - 1)
            }
        } header: {
            WrenListHeader(text: Date().formatted(.dateTime.month(.wide).year()))
        } footer: {
            if !summary.needsAmountRecorded.isEmpty {
                let count = summary.needsAmountRecorded.count
                WrenListFooter(text: "\(count) variable bill\(count == 1 ? "" : "s") went out automatically without a recorded amount. Entering the real figures keeps the trend meaningful.")
            }
        }
    }

    private func occurrenceRow(_ occurrence: BillOccurrence) -> some View {
        HStack(spacing: Space.m) {
            WrenTickBox(fill: settlementFill(occurrence), size: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(occurrence.label)
                    .font(WrenFont.detail)
                    .foregroundStyle(Color.wren.textPrimary)
                Text(settlementDetail(occurrence))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.wren.textSecondary)
            }
            Spacer(minLength: Space.s)
            Text(Money.format(cents: occurrence.recordedCents ?? occurrence.expectedCents))
                .font(WrenFont.detail)
                .monospacedDigit()
                .foregroundStyle(Color.wren.textSecondary)
        }
        .padding(.vertical, 2)
    }

    /// A greyed tick for assumed: settled, but not verified.
    private func settlementFill(_ occurrence: BillOccurrence) -> WrenTickBox.Fill {
        switch occurrence.settlement {
        case .recorded: return .done
        case .assumed: return .assumed
        case .outstanding: return .empty
        }
    }

    private func settlementDetail(_ occurrence: BillOccurrence) -> String {
        let day = occurrence.dueDate.formatted(.dateTime.day().month())
        switch occurrence.settlement {
        case .recorded: return day
        case .assumed:
            return occurrence.needsAmountRecorded
                ? "\(day) · assumed, amount not recorded"
                : "\(day) · assumed"
        case .outstanding: return day
        }
    }

    // MARK: - Forecast

    private var forecastSection: some View {
        let selected = selectedForecastMonth

        return Section {
            ForecastChart(months: forecast, calendar: calendar, selection: $selectedForecastMonth)
                .padding(.vertical, Space.s)
                .wrenRow(first: true, last: selected == nil)

            // Tapping a bar reveals that month's bills — the table view behind
            // the chart, rather than a tooltip that can't exist on a phone.
            if let selected {
                ForEach(Array(selected.occurrences.enumerated()), id: \.element.id) { index, occurrence in
                    HStack(spacing: Space.m) {
                        Text(occurrence.label)
                            .font(WrenFont.detail)
                            .foregroundStyle(Color.wren.textPrimary)
                        Spacer(minLength: Space.s)
                        Text(occurrence.dueDate.formatted(.dateTime.day().month()))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.wren.textSecondary)
                        Text(Money.format(cents: occurrence.expectedCents))
                            .font(WrenFont.detail)
                            .monospacedDigit()
                            .foregroundStyle(Color.wren.textPrimary)
                    }
                    .padding(.vertical, 2)
                    .wrenRow(last: index == selected.occurrences.count - 1)
                }
            }
        } header: {
            WrenListHeader(text: "Next 12 months")
        } footer: {
            WrenListFooter(text: selected == nil
                           ? "Tap a month to see what falls in it. The line is the 12-month average."
                           : "The line is the 12-month average.")
        }
    }

    // MARK: - By category

    private var categorySection: some View {
        let totals = BillReports.byCategory(specs)
        let maxMonthly = max(totals.map(\.monthlyCents).max() ?? 0, 1)

        return Section {
            ForEach(Array(totals.enumerated()), id: \.element.id) { index, total in
                VStack(alignment: .leading, spacing: Space.s) {
                    HStack(spacing: Space.m) {
                        Text(total.category)
                            .font(WrenFont.value)
                            .foregroundStyle(Color.wren.textPrimary)
                        Spacer(minLength: Space.s)
                        Text(Money.format(cents: total.monthlyCents))
                            .font(WrenFont.value)
                            .monospacedDigit()
                            .foregroundStyle(Color.wren.textPrimary)
                    }
                    // A meter per category: same single-series encoding as the
                    // forecast, magnitude by length only.
                    WrenMeter(fraction: Double(total.monthlyCents) / Double(maxMonthly))
                    Text("\(total.billCount) bill\(total.billCount == 1 ? "" : "s") · \(Money.formatWholeDollars(cents: total.annualCents)) a year")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.wren.textSecondary)
                }
                .padding(.vertical, Space.xs)
                .wrenRow(first: index == 0, last: index == totals.count - 1)
            }
        } header: {
            WrenListHeader(text: "By category")
        }
    }

    // MARK: - Variance

    private var varianceSection: some View {
        let variances = BillReports.variances(bills: specs, payments: payments)
        // Owner-qualified, so two bills sharing a name do not collide here either.
        let labels = Dictionary(uniqueKeysWithValues: specs.map {
            ($0.id, $0.paidBy.isEmpty ? $0.name : "\($0.name) · \($0.paidBy)")
        })

        return Group {
            if variances.isEmpty {
                Section {
                    Text("Record what you actually pay and the difference from the expected amount shows up here.")
                        .font(.subheadline)
                        .foregroundStyle(Color.wren.textSecondary)
                        .padding(.vertical, Space.xs)
                        .wrenRow(first: true, last: true)
                } header: {
                    WrenListHeader(text: "Expected vs actual")
                }
            } else {
                Section {
                    ForEach(Array(variances.enumerated()), id: \.element.billID) { index, variance in
                        HStack(spacing: Space.m) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(labels[variance.billID] ?? "Unknown")
                                    .font(WrenFont.value)
                                    .foregroundStyle(Color.wren.textPrimary)
                                Text("\(variance.paymentCount) payment\(variance.paymentCount == 1 ? "" : "s")")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(Color.wren.textSecondary)
                            }
                            Spacer(minLength: Space.s)
                            Text(differenceLabel(variance))
                                .font(WrenFont.value)
                                .monospacedDigit()
                                .foregroundStyle(variance.differenceCents > 0 ? Color.wren.alert : Color.wren.textPrimary)
                        }
                        .padding(.vertical, Space.xs)
                        .wrenRow(first: index == 0, last: index == variances.count - 1)
                    }
                } header: {
                    WrenListHeader(text: "Expected vs actual")
                } footer: {
                    WrenListFooter(text: "Worst overspend first. Positive means it cost more than the expected amount on the bill.")
                }
            }
        }
    }

    private func differenceLabel(_ variance: BillVariance) -> String {
        let sign = variance.differenceCents > 0 ? "+" : ""
        return "\(sign)\(Money.format(cents: variance.differenceCents))"
    }

    // MARK: - Export

    private var exportSection: some View {
        let exports: [(String, () -> String)] = [
            ("Bills and monthly equivalents", { BillCSV.bills(specs) }),
            ("Payment history", { BillCSV.payments(specs, payments: payments) }),
            ("12-month forecast", { BillCSV.forecast(forecast) })
        ]

        return Section {
            ForEach(Array(exports.enumerated()), id: \.offset) { index, export in
                Button {
                    exportText = export.1()
                } label: {
                    HStack(spacing: Space.m) {
                        Text(export.0)
                            .font(WrenFont.value)
                            .foregroundStyle(Color.wren.textPrimary)
                        Spacer(minLength: Space.s)
                        Image(systemName: "square.and.arrow.up")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.wren.textPrimary)
                    }
                    .padding(.vertical, Space.xs)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .wrenRow(first: index == 0, last: index == exports.count - 1)
            }
        } header: {
            WrenListHeader(text: "Export CSV")
        } footer: {
            WrenListFooter(text: "Opens the share sheet. Amounts are plain decimals for spreadsheets.")
        }
    }
}

/// `sheet(item:)` needs an Identifiable payload, and a bare String isn't one.
private struct ExportPayload: Identifiable {
    let text: String
    var id: Int { text.hashValue }

    init(_ text: String) { self.text = text }
}
