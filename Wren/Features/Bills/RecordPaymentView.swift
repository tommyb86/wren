import SwiftUI
import SwiftData
import WrenCore

/// Records what was actually paid, against the occurrence it settles.
///
/// The due date is picked from the bill's real occurrences rather than typed, so
/// a payment always lines up with something the schedule generated — that is
/// what lets "this month, paid vs outstanding" work.
@MainActor
struct RecordPaymentView: View {
    let bill: Bill

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var amountCents = 0
    @State private var dueDate: Date?
    @State private var paidAt = Date()
    @State private var didLoad = false

    private let calendar = Calendar.current

    /// Recent and upcoming occurrences, newest first, excluding ones already settled.
    private var candidateDueDates: [Date] {
        guard let schedule = bill.schedule else { return [] }
        let from = calendar.date(byAdding: .month, value: -14, to: Date()) ?? Date()
        let to = calendar.date(byAdding: .month, value: 2, to: Date()) ?? Date()
        let settled = Set((bill.payments ?? []).map { calendar.startOfDay(for: $0.dueDate) })

        return ScheduleEngine.occurrences(schedule, from: from, to: to, calendar: calendar)
            .filter { !settled.contains(calendar.startOfDay(for: $0)) }
            .sorted(by: >)
    }

    private var settlesOptions: [WrenOption<Date>] {
        candidateDueDates.map { WrenOption($0, $0.formatted(.dateTime.day().month().year())) }
    }

    private var canSave: Bool { dueDate != nil && amountCents > 0 }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MoneyField(label: "Amount paid", cents: $amountCents)
                        .wrenRow(first: true)
                    WrenDateRow(label: "Paid on", date: $paidAt, components: .date)
                        .wrenRow(last: true)
                } header: {
                    WrenListHeader(text: bill.name.isEmpty ? "Payment" : bill.name)
                } footer: {
                    WrenListFooter(text: bill.isVariableAmount
                                   ? "Expected \(Money.format(cents: bill.amountCents)) — enter what the bill actually came to."
                                   : "Expected \(Money.format(cents: bill.amountCents)).")
                }

                Section {
                    if let dueDate {
                        WrenMenuRow(
                            label: "Settles",
                            selection: Binding(get: { dueDate }, set: { self.dueDate = $0 }),
                            options: settlesOptions
                        )
                        .wrenRow(first: true, last: true)
                    } else {
                        Text("No unsettled occurrences found. Every recent bill already has a payment recorded.")
                            .font(.subheadline)
                            .foregroundStyle(Color.wren.textSecondary)
                            .padding(.vertical, Space.xs)
                            .wrenRow(first: true, last: true)
                    }
                } header: {
                    WrenListHeader(text: "Which bill this pays")
                } footer: {
                    WrenListFooter(text: "Recorded against the due date it settles, not the day you paid — so the reports stay accurate when you pay late.")
                }

                // The difference is the thing worth seeing before saving, so it
                // is a figure rather than something discovered later in Reports.
                if amountCents > 0, amountCents != bill.amountCents {
                    Section {
                        WrenOutcomeBox(
                            label: deltaCents > 0 ? "More than expected" : "Less than expected",
                            value: "\(deltaCents > 0 ? "+" : "")\(Money.format(cents: deltaCents))",
                            detail: "Expected \(Money.format(cents: bill.amountCents))"
                        )
                        .listRowInsets(EdgeInsets(top: Space.s, leading: Space.l, bottom: Space.s, trailing: Space.l))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            }
            .wrenListStyle()
            .navigationTitle("Record payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(WrenFont.value)
                        .foregroundStyle(Color.wren.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        WrenToolbarButton(title: "Save", isEnabled: canSave)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                }
            }
            .task { load() }
        }
    }

    private var deltaCents: Int { amountCents - bill.amountCents }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        // Default to the expected amount and the most recent unsettled occurrence.
        amountCents = bill.amountCents
        dueDate = candidateDueDates.first
    }

    private func save() {
        guard let dueDate else { return }

        let payment = BillPayment(paidAt: paidAt, amountCents: amountCents, dueDate: dueDate, bill: bill)
        context.insert(payment)
        if bill.payments == nil {
            bill.payments = [payment]
        } else {
            bill.payments?.append(payment)
        }

        do {
            try context.save()
        } catch {
            Logger.shared.error("bills", "payment save failed: \(error.localizedDescription)")
        }

        let delta = amountCents - bill.amountCents
        Logger.shared.info(
            "bills",
            "recorded \(Money.plainFormat(cents: amountCents)) for '\(bill.name)'"
                + " settling \(dueDate.formatted(date: .abbreviated, time: .omitted))"
                + (delta == 0 ? "" : " (\(delta > 0 ? "+" : "")\(Money.plainFormat(cents: delta)) vs expected)")
        )
        dismiss()
    }
}
