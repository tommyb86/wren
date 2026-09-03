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

    /// Suggestions, not a closed list — the field stays free text.
    private let categorySuggestions = ["Utilities", "Insurance", "Subscriptions", "Car", "Home", "Health"]

    var body: some View {
        NavigationStack {
            Form {
                // A string title and a footer are mutually exclusive overloads,
                // so the header goes in its own builder.
                Section {
                    TextField("Name", text: $name)
                    MoneyField(label: "Amount", cents: $amountCents)
                    Toggle("Amount varies", isOn: $isVariableAmount)
                } header: {
                    Text("Bill")
                } footer: {
                    Text(isVariableAmount
                         ? "The amount above is treated as an estimate. Recording what you actually pay is what drives the variance report."
                         : "A fixed amount, like a subscription or a premium.")
                }

                Section("Category") {
                    TextField("Category", text: $category)
                    if category.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Space.s) {
                                ForEach(categorySuggestions, id: \.self) { suggestion in
                                    Button(suggestion) { category = suggestion }
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(Color.wren.accent)
                                        .padding(.horizontal, Space.s)
                                        .padding(.vertical, Space.xs)
                                        .background(Color.wren.accentSoft, in: RoundedRectangle(cornerRadius: Radius.chip))
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    TextField("Paid by (optional)", text: $paidBy)
                }

                ScheduleEditor(draft: $draft, labels: .bills, calendar: calendar)

                Section {
                    Toggle("Pays automatically", isOn: $paysAutomatically)
                } footer: {
                    Text(automaticFooter)
                }

                Section {
                    Toggle("Active", isOn: $isActive)
                } footer: {
                    Text(normalisationFooter)
                }

                if isEditing {
                    Section {
                        Button("Delete bill", role: .destructive, action: delete)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.wren.background)
            .navigationTitle(isEditing ? "Edit bill" : "Add bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .task { load() }
        }
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

    /// Shows the normalisation working, so the monthly figure in the reports is
    /// never a number that appeared from nowhere.
    private var normalisationFooter: String {
        guard amountCents > 0 else { return "Enter an amount to see what it works out to." }
        let schedule = draft.schedule
        let monthly = BillingPeriod.monthlyEquivalentCents(amountCents: amountCents, schedule: schedule)
        let annual = BillingPeriod.annualCents(amountCents: amountCents, schedule: schedule)

        return "\(Money.format(cents: amountCents)) \(BillingPeriod.cadenceDescription(schedule))"
            + " is \(Money.format(cents: monthly)) a month"
            + " and \(Money.format(cents: annual)) a year."
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
