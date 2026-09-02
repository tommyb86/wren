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

    private let calendar = Calendar.current

    private var history: [BillPayment] {
        (bill.payments ?? []).sorted { $0.dueDate > $1.dueDate }
    }

    private var variance: BillVariance? {
        guard let spec = bill.spec else { return nil }
        return BillReports.variance(bill: spec, payments: bill.paymentRecords)
    }

    var body: some View {
        List {
            summarySection
            if let variance, variance.paymentCount > 0 {
                varianceSection(variance)
            }
            historySection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.wren.background)
        .navigationTitle(bill.name.isEmpty ? "Bill" : bill.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Record a payment") { isRecordingPayment = true }
                    Button("Edit bill") { isEditing = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
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
        Section {
            row("Amount", Money.format(cents: bill.amountCents)
                + (bill.isVariableAmount ? " (est.)" : ""))
            if let schedule = bill.schedule {
                row("Cadence", BillingPeriod.cadenceDescription(schedule).capitalized)
            }
            row("Monthly equivalent", Money.format(cents: bill.monthlyEquivalentCents))
            row("Annual", Money.format(cents: bill.annualCents))
            if let next = bill.nextDue(calendar: calendar) {
                row("Next due", next.formatted(.dateTime.weekday(.abbreviated).day().month().year()))
            }
            if !bill.category.isEmpty { row("Category", bill.category) }
            if !bill.paidBy.isEmpty { row("Paid by", bill.paidBy) }
        } footer: {
            Text("Bills are informative only — Wren doesn't send reminders for them.")
        }
    }

    /// Expected vs actual. On a variable bill this is the whole point.
    private func varianceSection(_ variance: BillVariance) -> some View {
        Section {
            row("Expected", Money.format(cents: variance.expectedCents))
            row("Actually paid", Money.format(cents: variance.actualCents))
            HStack {
                Text("Difference")
                    .font(.subheadline)
                    .foregroundStyle(Color.wren.textSecondary)
                Spacer()
                Text(differenceLabel(variance))
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    // Terracotta means "costs more than you thought", which is
                    // the one thing here worth flagging.
                    .foregroundStyle(variance.differenceCents > 0 ? Color.wren.alert : Color.wren.accent)
            }
        } header: {
            Text("Expected vs actual — \(variance.paymentCount) payment\(variance.paymentCount == 1 ? "" : "s")")
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
            } else {
                ForEach(history) { payment in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Money.format(cents: payment.amountCents))
                                .font(.subheadline.weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(Color.wren.textPrimary)
                            Text("for \(payment.dueDate.formatted(.dateTime.day().month().year()))")
                                .font(.caption)
                                .foregroundStyle(Color.wren.textSecondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(deltaLabel(payment))
                                .font(.caption.weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(payment.amountCents > bill.amountCents
                                                 ? Color.wren.alert : Color.wren.textSecondary)
                            Text("paid \(payment.paidAt.formatted(.dateTime.day().month()))")
                                .font(.caption2)
                                .foregroundStyle(Color.wren.textSecondary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) { delete(payment) }
                    }
                }
            }
        } header: {
            Text("Payment history")
        } footer: {
            if !history.isEmpty {
                Text("Compared against the \(Money.format(cents: bill.amountCents)) expected amount.")
            }
        }
    }

    private func deltaLabel(_ payment: BillPayment) -> String {
        let delta = payment.amountCents - bill.amountCents
        guard delta != 0 else { return "as expected" }
        return "\(delta > 0 ? "+" : "")\(Money.format(cents: delta))"
    }

    private func delete(_ payment: BillPayment) {
        Logger.shared.info("bills", "deleted a payment of \(Money.fallbackFormat(cents: payment.amountCents, showsCents: true)) from '\(bill.name)'")
        bill.payments?.removeAll { $0.persistentModelID == payment.persistentModelID }
        context.delete(payment)
        do {
            try context.save()
        } catch {
            Logger.shared.error("bills", "payment delete failed: \(error.localizedDescription)")
        }
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
