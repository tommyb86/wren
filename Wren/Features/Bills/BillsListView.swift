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
                Button { isAdding = true } label: { WrenToolbarIcon(systemName: "plus") }
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
            // The headline and where it leads are one box: the figure on top,
            // the way into Reports as the row beneath it.
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Money.format(cents: BillReports.monthlyCommitmentCents(specs)))
                        .font(WrenFont.title2)
                        .monospacedDigit()
                        .foregroundStyle(Color.wren.textPrimary)
                    Text("a month across \(activeCount) active bill\(activeCount == 1 ? "" : "s"), every cadence made monthly")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.wren.textSecondary)
                }
                .padding(.vertical, Space.xs)
                .wrenRow(first: true)

                NavigationLink {
                    ReportsView()
                } label: {
                    Text("Reports, forecast and export")
                        .font(WrenFont.value)
                        .foregroundStyle(Color.wren.textPrimary)
                        .padding(.vertical, Space.xs)
                }
                .wrenRow(last: true)
            }

            Section {
                ForEach(Array(bills.enumerated()), id: \.element.billID) { index, bill in
                    NavigationLink {
                        BillDetailView(bill: bill)
                    } label: {
                        row(bill)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) { delete(bill) }
                            .tint(Color.wren.alert)
                        Button("Edit") { editing = bill }
                            .tint(Color.wren.textPrimary)
                    }
                    .wrenRow(first: index == 0, last: index == bills.count - 1)
                }
            } header: {
                WrenListHeader(text: "Bills", trailing: "\(activeCount) active")
            }
        }
        .wrenListStyle()
    }

    private var activeCount: Int { bills.filter(\.isActive).count }

    private func row(_ bill: Bill) -> some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.s) {
                    Text(bill.name.isEmpty ? "Untitled bill" : bill.name)
                        .font(WrenFont.heading)
                        .foregroundStyle(bill.isActive ? Color.wren.textPrimary : Color.wren.textSecondary)
                    if bill.isVariableAmount {
                        WrenChip(text: "varies", tint: .wren.textPrimary, fill: .wren.accentSoft)
                    }
                }
                subtitle(bill)
                    .font(WrenFont.detail)
                    .foregroundStyle(Color.wren.textSecondary)
            }

            Spacer()

            if bill.isActive {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Money.formatWholeDollars(cents: bill.monthlyEquivalentCents))
                        .font(WrenFont.value)
                        .monospacedDigit()
                        .foregroundStyle(Color.wren.textPrimary)
                    Text("/mo")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.wren.textSecondary)
                }
            } else {
                WrenChip(text: "Paused", tint: .wren.textSecondary, fill: .wren.surface)
            }
        }
        .padding(.vertical, Space.xs)
    }

    /// Returns `Text` rather than a String so the owner's name can carry primary
    /// ink while the amount and cadence stay recessive — with two bills sharing a
    /// name, whose it is is the part being scanned for.
    private func subtitle(_ bill: Bill) -> Text {
        guard let schedule = bill.schedule else { return Text("No schedule") }

        let cadence = Text("\(Money.format(cents: bill.amountCents)) \(BillingPeriod.cadenceDescription(schedule))")
        guard !bill.paidBy.isEmpty else { return cadence }

        return cadence
            + Text(" · ")
            + Text(bill.paidBy).foregroundStyle(Color.wren.textPrimary)
    }

    private var emptyState: some View {
        VStack(spacing: Space.m) {
            WrenMark(size: 64)
                .padding(.bottom, Space.xs)
            Text("No bills yet")
                .font(WrenFont.title3)
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
        Task { await ReminderCoordinator.rebuild(context: context, calendar: calendar) }
    }
}
