import SwiftUI
import SwiftData
import WrenCore

/// The screen that makes the app worth opening. Bins, tasks and bills unified
/// into one agenda, actionable inline.
///
/// The bin-week card sits above the agenda deliberately: "what bin week is it?"
/// is a different question from "what needs doing tonight", and the plan asks
/// for both to be answerable at a glance.
@MainActor
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BinCollection.sortOrder) private var bins: [BinCollection]
    @Query(sort: \RecurringTask.sortOrder) private var tasks: [RecurringTask]
    @Query(sort: \Bill.sortOrder) private var bills: [Bill]
    @Query(sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]
    @StateObject private var scheduler = NotificationScheduler.shared

    @State private var recordingPaymentFor: Bill?

    private let calendar = Calendar.current

    private var agenda: TodayAgenda {
        TodayAgenda.build(
            bins: bins.filter(\.isActive).compactMap(\.binSchedule),
            tasks: tasks.compactMap { task in
                task.schedule.map {
                    TaskSpec(
                        id: task.taskID,
                        schedule: $0,
                        completedDueDates: task.completedDueDates,
                        isActive: task.isActive
                    )
                }
            },
            bills: bills.compactMap(\.spec),
            payments: bills.flatMap(\.paymentRecords),
            calendar: calendar
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    header

                    if scheduler.authorizationStatus == .denied && !(bins.isEmpty && tasks.isEmpty) {
                        permissionWarning
                    }

                    if !bins.isEmpty {
                        NavigationLink { BinsListView() } label: {
                            BinWeekCard(bins: bins, calendar: calendar)
                        }
                        .buttonStyle(.plain)
                    }

                    let current = agenda
                    if current.isEmpty {
                        emptyState
                    } else {
                        bucket("Needs doing", items: current.overdue, isAlert: true)
                        bucket("Today", items: current.today)
                        bucket("Tomorrow", items: current.tomorrow)
                        bucket("Later this week", items: current.laterThisWeek)
                    }

                    quickLinks
                }
                .padding(Space.l)
            }
            .background(Color.wren.background)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $recordingPaymentFor) { bill in
                RecordPaymentView(bill: bill)
            }
        }
        .task {
            await scheduler.refreshAuthorizationStatus()
            await ReminderCoordinator.rebuild(context: context, calendar: calendar)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            WrenTitle(text: "Today")
            Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.footnote)
                .foregroundStyle(Color.wren.textSecondary)
        }
        .padding(.top, Space.s)
    }

    private var permissionWarning: some View {
        WrenCard {
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Reminders are switched off")
                    .font(.headline)
                    .foregroundStyle(Color.wren.alert)
                Text("Wren can't notify you about bin nights or tasks until notifications are allowed in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(Color.wren.textSecondary)
            }
        }
    }

    // MARK: - Agenda

    @ViewBuilder
    private func bucket(_ title: String, items: [TodayItem], isAlert: Bool = false) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Space.m) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isAlert ? Color.wren.alert : Color.wren.textSecondary)

                VStack(spacing: 0) {
                    let models = items.compactMap(rowModel)
                    ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                        TodayRow(model: model, calendar: calendar)
                            .padding(.horizontal, Space.m)
                            .padding(.vertical, Space.xs)
                        if index < models.count - 1 {
                            Divider().overlay(Color.wren.divider)
                        }
                    }
                }
                .background(Color.wren.surface, in: RoundedRectangle(cornerRadius: Radius.card))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card)
                        .strokeBorder(Color.wren.divider, lineWidth: 1)
                )
            }
        }
    }

    /// Resolves an agenda item against the store. Returns nil if the source has
    /// been deleted since the agenda was built.
    private func rowModel(_ item: TodayItem) -> TodayRowModel? {
        switch item.kind {
        case .bin:
            guard let bin = bins.first(where: { $0.binID == item.sourceID }) else { return nil }
            return TodayRowModel(
                item: item,
                title: bin.name.isEmpty ? "Bin" : bin.name,
                detail: detail(for: item, suffix: "collection"),
                tint: Color(binHex: bin.colorHex),
                action: nil
            )

        case .task:
            guard let task = tasks.first(where: { $0.taskID == item.sourceID }) else { return nil }
            return TodayRowModel(
                item: item,
                title: task.title.isEmpty ? "Untitled task" : task.title,
                detail: detail(for: item, suffix: nil),
                tint: nil,
                action: { TaskStore.complete(task, context: context, calendar: calendar) }
            )

        case .bill:
            guard let bill = bills.first(where: { $0.billID == item.sourceID }) else { return nil }
            return TodayRowModel(
                item: item,
                title: bill.paidBy.isEmpty ? bill.name : "\(bill.name) · \(bill.paidBy)",
                detail: detail(for: item, suffix: nil),
                tint: nil,
                action: { recordingPaymentFor = bill }
            )
        }
    }

    private func detail(for item: TodayItem, suffix: String?) -> String {
        let time = item.date.formatted(date: .omitted, time: .shortened)
        let base: String

        switch item.status {
        case .overdue(let days):
            switch days {
            case 0: base = "Was due at \(time)"
            case 1: base = "Overdue since yesterday"
            default: base = "Overdue by \(days) days"
            }
        case .dueToday:
            base = suffix == "collection" ? "Out tonight, \(time)" : "Due at \(time)"
        case .dueTomorrow:
            base = "Tomorrow, \(time)"
        case .upcoming:
            base = item.date.formatted(.dateTime.weekday(.wide).day().month())
        }
        return base
    }

    private var emptyState: some View {
        WrenCard {
            VStack(alignment: .leading, spacing: Space.s) {
                Text(bins.isEmpty && tasks.isEmpty && bills.isEmpty
                     ? "Nothing set up yet"
                     : "Nothing this week")
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(Color.wren.textPrimary)
                Text(bins.isEmpty && tasks.isEmpty && bills.isEmpty
                     ? "Add a bin, a task or a bill and it turns up here."
                     : "No bins, tasks or bills due in the next seven days.")
                    .font(.subheadline)
                    .foregroundStyle(Color.wren.textSecondary)
            }
        }
    }

    // MARK: - Navigation

    private var quickLinks: some View {
        VStack(spacing: 0) {
            link("Bins", detail: binsDetail) { BinsListView() }
            Divider().overlay(Color.wren.divider)
            link("Tasks", detail: tasksDetail) { TasksListView() }
            Divider().overlay(Color.wren.divider)
            link("Bills", detail: billsDetail) { BillsListView() }
            Divider().overlay(Color.wren.divider)
            link("Receipts", detail: receiptsDetail) { ReceiptsListView() }
            Divider().overlay(Color.wren.divider)
            link("Diagnostics", detail: "\(scheduler.pending.count) reminder\(scheduler.pending.count == 1 ? "" : "s") scheduled") { DiagnosticsView() }
        }
        .background(Color.wren.surface, in: RoundedRectangle(cornerRadius: Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(Color.wren.divider, lineWidth: 1)
        )
    }

    private func link<Destination: View>(
        _ title: String,
        detail: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.wren.textPrimary)
                Spacer()
                Text(detail)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.wren.textSecondary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.wren.textSecondary)
            }
            .padding(Space.m)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var binsDetail: String {
        bins.isEmpty ? "Not set up" : "\(bins.filter(\.isActive).count) active"
    }

    private var tasksDetail: String {
        guard !tasks.isEmpty else { return "Not set up" }
        let overdue = agenda.overdue.filter { $0.kind == .task }.count
        return overdue > 0 ? "\(overdue) overdue" : "\(tasks.filter(\.isActive).count) active"
    }

    private var receiptsDetail: String {
        let current = FinancialYear.current(calendar: calendar)
        let thisYear = receipts.filter { current.contains($0.date, calendar: calendar) }
        guard !thisYear.isEmpty else { return receipts.isEmpty ? "Not set up" : "None this FY" }
        let total = thisYear.reduce(0) { $0 + $1.amountCents }
        return "\(Money.formatWholeDollars(cents: total)) in \(current.label)"
    }

    private var billsDetail: String {
        let specs = bills.compactMap(\.spec)
        guard !specs.isEmpty else { return "Not set up" }
        return "\(Money.formatWholeDollars(cents: BillReports.monthlyCommitmentCents(specs)))/mo"
    }
}
