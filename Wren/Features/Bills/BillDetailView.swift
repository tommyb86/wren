import SwiftUI
import SwiftData
import WrenCore

/// One bill's own page: what it costs normalised, what's actually been paid, and
/// the variance between the two. This is where "has the power bill gone up?"
/// gets answered.
@MainActor
struct BillDetailView: View {
    let bill: Bill

    @Environment(\.modelContext) private var context
    @State private var isRecordingPayment = false
    @State private var isEditing = false
    @State private var selectedPoint: TrendPoint?

    private let calendar = Calendar.current

    private var history: [BillPayment] {
        (bill.payments ?? []).sorted { $0.dueDate > $1.dueDate }
    }

    private var variance: BillVariance? {
        guard let spec = bill.spec else { return nil }
        return BillReports.variance(bill: spec, payments: bill.paymentRecords)
    }

    private var trend: PaymentTrend {
        BillReports.trend(billID: bill.billID, payments: bill.paymentRecords)
    }

    var body: some View {
        List {
            summarySection
            // Only for variable bills: a fixed one would draw a flat line and
            // say nothing. Below three points the history list is strictly
            // better, which is `isChartable`.
            if bill.isVariableAmount, trend.isChartable {
                trendSection
            }
            if let variance, variance.paymentCount > 0 {
                varianceSection(variance)
            }
            historySection
        }
        .wrenListStyle()
        .navigationTitle(bill.name.isEmpty ? "Bill" : bill.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Record a payment") { isRecordingPayment = true }
                    Button("Edit bill") { isEditing = true }
                } label: {
                    WrenToolbarIcon(systemName: "ellipsis")
                }
                .accessibilityLabel("Bill actions")
            }
        }
        .sheet(isPresented: $isRecordingPayment) {
            RecordPaymentView(bill: bill)
        }
        .sheet(isPresented: $isEditing) {
            BillEditorView(bill: bill, existingBillCount: 0)
        }
    }

    private var summarySection: some View {
        var stats: [(String, String)] = [
            ("Amount", Money.format(cents: bill.amountCents) + (bill.isVariableAmount ? " (est.)" : ""))
        ]
        if let schedule = bill.schedule {
            stats.append(("Cadence", BillingPeriod.cadenceDescription(schedule).capitalized))
        }
        stats.append(("Monthly equivalent", Money.format(cents: bill.monthlyEquivalentCents)))
        stats.append(("Annual", Money.format(cents: bill.annualCents)))
        if let next = bill.nextDue(calendar: calendar) {
            stats.append(("Next due", next.formatted(.dateTime.weekday(.abbreviated).day().month().year())))
        }
        // Shown beside the estimate, never replacing it — the monthly
        // commitment is meant to be a stable figure, not one that drifts as
        // history accumulates.
        if let average = BillReports.recordedAverageCents(billID: bill.billID, payments: bill.paymentRecords) {
            stats.append(("Recorded average", Money.format(cents: average)))
        }
        if !bill.category.isEmpty { stats.append(("Category", bill.category)) }
        if !bill.paidBy.isEmpty { stats.append(("Paid by", bill.paidBy)) }
        if bill.paysAutomatically { stats.append(("Payment", "Automatic")) }

        return Section {
            ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                WrenStatRow(label: stat.0, value: stat.1)
                    .wrenRow(first: index == 0, last: index == stats.count - 1)
            }
        } header: {
            WrenListHeader(text: bill.isActive ? "This bill" : "Paused")
        } footer: {
            WrenListFooter(text: bill.paysAutomatically
                           ? "Pays automatically, so occurrences count as settled once due. Wren has no bank feed, so that's an assumption — and the amount is only ever what you record."
                           : "Bills are informative only — Wren doesn't send reminders for them.")
        }
    }

    private var trendSection: some View {
        let current = trend

        return Section {
            PaymentTrendChart(
                trend: current,
                expectedCents: bill.amountCents,
                selection: $selectedPoint
            )
            .wrenRow(first: true, last: true)
        } header: {
            WrenListHeader(text: "Recorded payments")
        } footer: {
            // Says what the picture does and does not support. Seasonal bills
            // rise and fall for reasons that have nothing to do with price.
            WrenListFooter(text: "Dashed line is the \(Money.format(cents: bill.amountCents)) expected amount."
                           + " Range \(Money.format(cents: current.minCents))–\(Money.format(cents: current.maxCents))."
                           + " Seasonal bills swing on their own, so comparing the same period a year apart says more than the shape here.")
        }
    }

    /// Expected vs actual. On a variable bill this is the whole point.
    private func varianceSection(_ variance: BillVariance) -> some View {
        Section {
            WrenStatRow(label: "Expected", value: Money.format(cents: variance.expectedCents))
                .wrenRow(first: true)
            WrenStatRow(label: "Actually paid", value: Money.format(cents: variance.actualCents))
                .wrenRow()
            // Red means "costs more than you thought", which is the one thing
            // here worth flagging.
            WrenStatRow(
                label: "Difference",
                value: differenceLabel(variance),
                valueColor: variance.differenceCents > 0 ? .wren.alert : .wren.textPrimary,
                emphasised: true
            )
            .wrenRow(last: true)
        } header: {
            WrenListHeader(
                text: "Expected vs actual",
                trailing: "\(variance.paymentCount) payment\(variance.paymentCount == 1 ? "" : "s")"
            )
        }
    }

    private func differenceLabel(_ variance: BillVariance) -> String {
        let amount = Money.format(cents: variance.differenceCents)
        guard let percent = variance.percentDifference else { return amount }
        let sign = variance.differenceCents > 0 ? "+" : ""
        return "\(sign)\(amount) (\(sign)\(String(format: "%.1f", percent))%)"
    }

    private var historySection: some View {
        Section {
            if history.isEmpty {
                Text("No payments recorded yet. Recording what you actually pay is what makes the reports honest.")
                    .font(.subheadline)
                    .foregroundStyle(Color.wren.textSecondary)
                    .padding(.vertical, Space.xs)
                    .wrenRow(first: true, last: true)
            } else {
                ForEach(Array(history.enumerated()), id: \.element.persistentModelID) { index, payment in
                    paymentRow(payment)
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) { delete(payment) }
                                .tint(Color.wren.alert)
                        }
                        .wrenRow(first: index == 0, last: index == history.count - 1)
                }
            }
        } header: {
            WrenListHeader(text: "Payment history")
        } footer: {
            if !history.isEmpty {
                WrenListFooter(text: "Compared against the \(Money.format(cents: bill.amountCents)) expected amount.")
            }
        }
    }

    private func paymentRow(_ payment: BillPayment) -> some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Money.format(cents: payment.amountCents))
                    .font(WrenFont.heading)
                    .monospacedDigit()
                    .foregroundStyle(Color.wren.textPrimary)
                Text("for \(payment.dueDate.formatted(.dateTime.day().month().year()))")
                    .font(WrenFont.detail)
                    .foregroundStyle(Color.wren.textSecondary)
            }
            Spacer(minLength: Space.s)
            VStack(alignment: .trailing, spacing: 2) {
                Text(deltaLabel(payment))
                    .font(WrenFont.detail)
                    .monospacedDigit()
                    .foregroundStyle(payment.amountCents > bill.amountCents
                                     ? Color.wren.alert : Color.wren.textSecondary)
                Text("paid \(payment.paidAt.formatted(.dateTime.day().month()))")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.wren.textSecondary)
            }
        }
        .padding(.vertical, Space.xs)
    }

    private func deltaLabel(_ payment: BillPayment) -> String {
        let delta = payment.amountCents - bill.amountCents
        guard delta != 0 else { return "as expected" }
        return "\(delta > 0 ? "+" : "")\(Money.format(cents: delta))"
    }

    private func delete(_ payment: BillPayment) {
        Logger.shared.info("bills", "deleted a payment of \(Money.plainFormat(cents: payment.amountCents)) from '\(bill.name)'")
        bill.payments?.removeAll { $0.persistentModelID == payment.persistentModelID }
        context.delete(payment)
        do {
            try context.save()
        } catch {
            Logger.shared.error("bills", "payment delete failed: \(error.localizedDescription)")
        }
    }
}
