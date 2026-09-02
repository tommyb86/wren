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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MoneyField(label: "Amount paid", cents: $amountCents)
                    DatePicker("Paid on", selection: $paidAt, displayedComponents: .date)
                } footer: {
                    Text(bill.isVariableAmount
                         ? "Expected \(Money.format(cents: bill.amountCents)) — enter what the bill actually came to."
                         : "Expected \(Money.format(cents: bill.amountCents)).")
                }

                Section {
                    if candidateDueDates.isEmpty {
                        Text("No unsettled occurrences found. Every recent bill already has a payment recorded.")
                            .font(.subheadline)
                            .foregroundStyle(Color.wren.textSecondary)
                    } else {
                        Picker("Settles", selection: $dueDate) {
                            ForEach(candidateDueDates, id: \.self) { date in
                                Text(date.formatted(.dateTime.day().month().year()))
                                    .tag(Date?.some(date))
                            }
                        }
                    }
                } header: {
                    Text("Which bill this pays")
                } footer: {
                    Text("Recorded against the due date it settles, not the day you paid — so the reports stay accurate when you pay late.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.wren.background)
            .navigationTitle("Record payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(dueDate == nil || amountCents == 0)
                }
            }
            .task { load() }
        }
    }

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
            "recorded \(Money.fallbackFormat(cents: amountCents, showsCents: true)) for '\(bill.name)'"
                + " settling \(dueDate.formatted(date: .abbreviated, time: .omitted))"
                + (delta == 0 ? "" : " (\(delta > 0 ? "+" : "")\(Money.fallbackFormat(cents: delta, showsCents: true)) vs expected)")
        )
        dismiss()
    }
}
