import SwiftUI
import SwiftData
import WrenCore

@MainActor
struct BillsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Bill.sortOrder) private var bills: [Bill]

    @State private var editing: Bill?
    @State private var isAdding = false

    private let calendar = Calendar.current

    private var specs: [BillSpec] { bills.compactMap(\.spec) }

    var body: some View {
        Group {
            if bills.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(Color.wren.background)
        .navigationTitle("Bills")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isAdding = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add bill")
            }
        }
        .sheet(isPresented: $isAdding) {
            BillEditorView(bill: nil, existingBillCount: bills.count)
        }
        .sheet(item: $editing) { bill in
            BillEditorView(bill: bill, existingBillCount: bills.count)
        }
    }

    private var list: some View {
        List {
            Section {
                NavigationLink {
                    ReportsView()
                } label: {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(Money.format(cents: BillReports.monthlyCommitmentCents(specs)))
                            .font(.system(.title2, design: .serif))
                            .monospacedDigit()
                            .foregroundStyle(Color.wren.textPrimary)
                        Text("a month across \(activeCount) active bill\(activeCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(Color.wren.textSecondary)
                    }
                    .padding(.vertical, Space.xs)
                }
            } footer: {
                Text("Every bill converted to a monthly equivalent, so different cadences are comparable.")
            }

            Section("Bills") {
                ForEach(bills) { bill in
                    NavigationLink {
                        BillDetailView(bill: bill)
                    } label: {
                        row(bill)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) { delete(bill) }
                        Button("Edit") { editing = bill }
                            .tint(Color.wren.accent)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var activeCount: Int { bills.filter(\.isActive).count }

    private func row(_ bill: Bill) -> some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.xs) {
                    Text(bill.name.isEmpty ? "Untitled bill" : bill.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.wren.textPrimary)
                    if bill.isVariableAmount {
                        Text("varies")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.wren.accent)
                            .padding(.horizontal, Space.xs)
                            .padding(.vertical, 1)
                            .background(Color.wren.accentSoft, in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                Text(subtitle(bill))
                    .font(.caption)
                    .foregroundStyle(Color.wren.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if bill.isActive {
                    Text(Money.format(cents: bill.monthlyEquivalentCents))
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.wren.textPrimary)
                    Text("/mo")
                        .font(.caption2)
                        .foregroundStyle(Color.wren.textSecondary)
                } else {
                    Text("Paused")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.wren.textSecondary)
                }
            }
        }
        .padding(.vertical, Space.xs)
    }

    private func subtitle(_ bill: Bill) -> String {
        guard let schedule = bill.schedule else { return "No schedule" }
        let amount = Money.format(cents: bill.amountCents)
        return "\(amount) \(BillingPeriod.cadenceDescription(schedule))"
    }

    private var emptyState: some View {
        VStack(spacing: Space.m) {
            WrenMark(size: 64)
                .padding(.bottom, Space.xs)
            Text("No bills yet")
                .font(.system(.title3, design: .serif))
                .foregroundStyle(Color.wren.textPrimary)
            Text("Add what the household pays and Wren works out what it costs a month — whatever cadence each bill arrives on.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.wren.textSecondary)
            Button("Add your first bill") { isAdding = true }
                .buttonStyle(WrenPrimaryButtonStyle())
                .padding(.top, Space.s)
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func delete(_ bill: Bill) {
        Logger.shared.info("bills", "deleted '\(bill.name)'")
        context.delete(bill)
        do {
            try context.save()
        } catch {
            Logger.shared.error("bills", "delete failed: \(error.localizedDescription)")
        }
    }
}
