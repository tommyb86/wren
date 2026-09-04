import SwiftUI
import SwiftData
import WrenCore

@MainActor
struct BillEditorView: View {
    /// nil when adding.
    let bill: Bill?
    let existingBillCount: Int

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var amountCents = 0
    @State private var isVariableAmount = false
    @State private var category = ""
    @State private var paidBy = ""
    @State private var paysAutomatically = false
    @State private var isActive = true
    @State private var draft = ScheduleDraft()
    @State private var didLoad = false

    private let calendar = Calendar.current

    private var isEditing: Bool { bill != nil }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Suggestions, not a closed list — the field stays free text.
    private let categorySuggestions = ["Utilities", "Insurance", "Subscriptions", "Car", "Home", "Health"]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    WrenTextRow(label: "Name", text: $name, placeholder: "AGL")
                        .wrenRow(first: true)
                    MoneyField(
                        label: "Amount",
                        cents: $amountCents,
                        note: isVariableAmount ? "estimate" : nil
                    )
                    .wrenRow()
                    WrenToggleRow(label: "Amount varies", isOn: $isVariableAmount)
                        .wrenRow(last: true)
                } header: {
                    WrenListHeader(text: "Bill")
                } footer: {
                    WrenListFooter(text: isVariableAmount
                                   ? "The amount above is treated as an estimate. Recording what you actually pay is what drives the variance report."
                                   : "A fixed amount, like a subscription or a premium.")
                }

                Section {
                    WrenTextRow(label: "Category", text: $category, placeholder: "None")
                        .wrenRow(first: true)
                    if category.isEmpty {
                        WrenSuggestionRow(label: "Common ones", suggestions: categorySuggestions) {
                            category = $0
                        }
                        .wrenRow()
                    }
                    WrenTextRow(label: "Paid by", text: $paidBy, placeholder: "Optional")
                        .wrenRow(last: true)
                } header: {
                    WrenListHeader(text: "Category")
                }

                ScheduleEditor(draft: $draft, labels: .bills, calendar: calendar)

                // The whole point of a bill is what it costs a month, so the
                // normalisation is a figure rather than a footnote.
                if amountCents > 0 {
                    Section {
                        WrenOutcomeBox(
                            label: "Works out to",
                            value: Money.format(cents: monthlyCents),
                            unit: "a month",
                            detail: "\(Money.format(cents: annualCents)) a year · \(Money.format(cents: weeklyCents)) a week"
                        )
                        .listRowInsets(EdgeInsets(top: Space.s, leading: Space.l, bottom: Space.s, trailing: Space.l))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }

                Section {
                    WrenToggleRow(label: "Pays automatically", isOn: $paysAutomatically)
                        .wrenRow(first: true)
                    WrenToggleRow(label: "Active", isOn: $isActive)
                        .wrenRow(last: true)
                } footer: {
                    WrenListFooter(text: automaticFooter)
                }

                if isEditing {
                    Section {
                        Button("Delete bill", action: delete)
                            .buttonStyle(WrenDestructiveButtonStyle())
                            .listRowInsets(EdgeInsets(top: Space.l, leading: Space.l, bottom: Space.s, trailing: Space.l))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
            }
            .wrenListStyle()
            .navigationTitle(isEditing ? "Edit bill" : "Add bill")
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

    private var monthlyCents: Int {
        BillingPeriod.monthlyEquivalentCents(amountCents: amountCents, schedule: draft.schedule)
    }

    private var annualCents: Int {
        BillingPeriod.annualCents(amountCents: amountCents, schedule: draft.schedule)
    }

    private var weeklyCents: Int {
        BillingPeriod.weeklyEquivalentCents(amountCents: amountCents, schedule: draft.schedule)
    }

    /// States plainly what the app does and doesn't know. Wren has no bank feed,
    /// so "settled" is an assumption — and on a variable bill the amount is
    /// still worth recording, or the trend disappears.
    private var automaticFooter: String {
        guard paysAutomatically else {
            return "Off: occurrences stay outstanding until you record a payment."
        }
        return isVariableAmount
            ? "Direct debit. Nothing to tick — occurrences count as settled once the due date passes. Wren can't know the real amount, so it'll keep a list of ones worth entering to preserve the trend."
            : "Direct debit. Nothing to tick — occurrences count as settled once the due date passes, valued at the expected amount. Wren can't verify it actually went out."
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true

        guard let bill else {
            var draftValue = ScheduleDraft()
            draftValue.frequency = .monthly
            draftValue.anchorDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
            draft = draftValue
            return
        }

        name = bill.name
        amountCents = bill.amountCents
        isVariableAmount = bill.isVariableAmount
        category = bill.category
        paidBy = bill.paidBy
        paysAutomatically = bill.paysAutomatically
        isActive = bill.isActive
        if let schedule = bill.schedule {
            draft = ScheduleDraft(schedule)
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)

        if let bill {
            bill.name = trimmed
            bill.amountCents = amountCents
            bill.isVariableAmount = isVariableAmount
            bill.category = category.trimmingCharacters(in: .whitespaces)
            bill.paidBy = paidBy.trimmingCharacters(in: .whitespaces)
            bill.paysAutomatically = paysAutomatically
            bill.isActive = isActive
            bill.apply(draft.schedule)
            Logger.shared.info("bills", "updated '\(trimmed)' — \(Money.plainFormat(cents: amountCents)) \(BillingPeriod.cadenceDescription(draft.schedule))")
        } else {
            let created = Bill(
                name: trimmed,
                amountCents: amountCents,
                isVariableAmount: isVariableAmount,
                schedule: draft.schedule,
                category: category.trimmingCharacters(in: .whitespaces),
                paidBy: paidBy.trimmingCharacters(in: .whitespaces),
                paysAutomatically: paysAutomatically,
                isActive: isActive,
                sortOrder: existingBillCount
            )
            context.insert(created)
            Logger.shared.info("bills", "added '\(trimmed)' — \(Money.plainFormat(cents: amountCents)) \(BillingPeriod.cadenceDescription(draft.schedule))")
        }

        do {
            try context.save()
        } catch {
            Logger.shared.error("bills", "save failed: \(error.localizedDescription)")
        }
        dismiss()
    }

    private func delete() {
        guard let bill else { return }
        Logger.shared.info("bills", "deleted '\(bill.name)'")
        context.delete(bill)
        do {
            try context.save()
        } catch {
            Logger.shared.error("bills", "delete failed: \(error.localizedDescription)")
        }
        dismiss()
    }
}
