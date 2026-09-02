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
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.wren.background)
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
        Section {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(Money.format(cents: BillReports.monthlyCommitmentCents(specs)))
                    .font(.system(.largeTitle, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(Color.wren.textPrimary)
                Text("a month")
                    .font(.subheadline)
                    .foregroundStyle(Color.wren.textSecondary)
            }
            .padding(.vertical, Space.xs)

            row("Annual", Money.format(cents: BillReports.annualCommitmentCents(specs)))
            row("Weekly", Money.format(cents: weeklyCents))
        } header: {
            Text("Monthly commitment")
        } footer: {
            Text("Every bill converted to a monthly equivalent. A quarterly bill counts as a third of itself each month, so this is what the household costs on average — not what lands this month.")
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

        return Section {
            row("Due", Money.format(cents: summary.dueCents))
            row("Paid", Money.format(cents: summary.paidCents))
            HStack {
                Text("Outstanding")
                    .font(.subheadline)
                    .foregroundStyle(Color.wren.textSecondary)
                Spacer()
                Text(Money.format(cents: summary.outstandingCents))
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.wren.textPrimary)
            }

            ForEach(summary.occurrences) { occurrence in
                HStack {
                    Image(systemName: occurrence.isPaid ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                        .foregroundStyle(occurrence.isPaid ? Color.wren.accent : Color.wren.textSecondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(occurrence.name)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.wren.textPrimary)
                        Text(occurrence.dueDate.formatted(.dateTime.day().month()))
                            .font(.caption2)
                            .foregroundStyle(Color.wren.textSecondary)
                    }
                    Spacer()
                    Text(Money.format(cents: occurrence.paidCents ?? occurrence.expectedCents))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Color.wren.textSecondary)
                }
            }
        } header: {
            Text(Date().formatted(.dateTime.month(.wide).year()))
        }
    }

    // MARK: - Forecast

    private var forecastSection: some View {
        Section {
            ForecastChart(months: forecast, calendar: calendar, selection: $selectedForecastMonth)
                .padding(.vertical, Space.s)

            // Tapping a bar reveals that month's bills — the table view behind
            // the chart, rather than a tooltip that can't exist on a phone.
            if let selected = selectedForecastMonth {
                ForEach(selected.occurrences) { occurrence in
                    HStack {
                        Text(occurrence.name)
                            .font(.caption)
                            .foregroundStyle(Color.wren.textPrimary)
                        Spacer()
                        Text(occurrence.dueDate.formatted(.dateTime.day().month()))
                            .font(.caption2)
                            .foregroundStyle(Color.wren.textSecondary)
                        Text(Money.format(cents: occurrence.expectedCents))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Color.wren.textPrimary)
                    }
                }
            }
        } header: {
            Text("Next 12 months")
        } footer: {
            Text(selectedForecastMonth == nil
                 ? "Tap a month to see what falls in it. The line is the 12-month average."
                 : "The line is the 12-month average.")
        }
    }

    // MARK: - By category

    private var categorySection: some View {
        let totals = BillReports.byCategory(specs)
        let maxMonthly = max(totals.map(\.monthlyCents).max() ?? 0, 1)

        return Section {
            ForEach(totals) { total in
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack {
                        Text(total.category)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.wren.textPrimary)
                        Spacer()
                        Text(Money.format(cents: total.monthlyCents))
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(Color.wren.textPrimary)
                    }
                    // A bar per category: same single-series encoding as the
                    // forecast, magnitude by length only.
                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.wren.accent.opacity(0.72))
                            .frame(width: geometry.size.width * CGFloat(total.monthlyCents) / CGFloat(maxMonthly))
                    }
                    .frame(height: 4)
                    Text("\(total.billCount) bill\(total.billCount == 1 ? "" : "s") · \(Money.formatWholeDollars(cents: total.annualCents)) a year")
                        .font(.caption2)
                        .foregroundStyle(Color.wren.textSecondary)
                }
                .padding(.vertical, Space.xs)
            }
        } header: {
            Text("By category")
        }
    }

    // MARK: - Variance

    private var varianceSection: some View {
        let variances = BillReports.variances(bills: specs, payments: payments)
        let names = Dictionary(uniqueKeysWithValues: specs.map { ($0.id, $0.name) })

        return Group {
            if variances.isEmpty {
                Section {
                    Text("Record what you actually pay and the difference from the expected amount shows up here.")
                        .font(.subheadline)
                        .foregroundStyle(Color.wren.textSecondary)
                } header: {
                    Text("Expected vs actual")
                }
            } else {
                Section {
                    ForEach(variances, id: \.billID) { variance in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(names[variance.billID] ?? "Unknown")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Color.wren.textPrimary)
                                Text("\(variance.paymentCount) payment\(variance.paymentCount == 1 ? "" : "s")")
                                    .font(.caption2)
                                    .foregroundStyle(Color.wren.textSecondary)
                            }
                            Spacer()
                            Text(differenceLabel(variance))
                                .font(.subheadline.weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(variance.differenceCents > 0 ? Color.wren.alert : Color.wren.accent)
                        }
                    }
                } header: {
                    Text("Expected vs actual")
                } footer: {
                    Text("Worst overspend first. Positive means it cost more than the expected amount on the bill.")
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
        Section {
            Button("Bills and monthly equivalents") {
                exportText = BillCSV.bills(specs)
            }
            Button("Payment history") {
                exportText = BillCSV.payments(specs, payments: payments)
            }
            Button("12-month forecast") {
                exportText = BillCSV.forecast(forecast)
            }
        } header: {
            Text("Export CSV")
        } footer: {
            Text("Opens the share sheet. Amounts are plain decimals for spreadsheets.")
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Color.wren.accent)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.wren.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Color.wren.textPrimary)
        }
    }
}

/// `sheet(item:)` needs an Identifiable payload, and a bare String isn't one.
private struct ExportPayload: Identifiable {
    let text: String
    var id: Int { text.hashValue }

    init(_ text: String) { self.text = text }
}
