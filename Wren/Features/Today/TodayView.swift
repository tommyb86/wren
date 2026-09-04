import SwiftUI
import SwiftData
import WrenCore

/// The screen that makes the app worth opening. Reads like a diary page: the
/// date, one sentence on what the day holds, four tiles for the sections, then
/// the week as a dated list with everything actionable inline.
///
/// Bin week no longer owns a card. "What bin week is it?" is answered in the
/// Bins tile and by the bin rows themselves, whose copy says which night to
/// put them out — the collection date alone was the confusing part.
@MainActor
struct TodayView: View {
    @Environment(\.wrenTheme) private var theme
    @Environment(\.modelContext) private var context
    @Query(sort: \BinCollection.sortOrder) private var bins: [BinCollection]
    @Query(sort: \RecurringTask.sortOrder) private var tasks: [RecurringTask]
    @Query(sort: \Bill.sortOrder) private var bills: [Bill]
    @Query(sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]
    @StateObject private var scheduler = NotificationScheduler.shared

    @State private var recordingPaymentFor: Bill?
    @State private var lastSettled: SettledTask?

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

    private var hasAnythingSetUp: Bool {
        !(bins.isEmpty && tasks.isEmpty && bills.isEmpty)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                let current = agenda
                VStack(alignment: .leading, spacing: Space.xl) {
                    header(current)

                    if scheduler.authorizationStatus == .denied && hasAnythingSetUp {
                        permissionWarning
                    }

                    tiles(current)

                    if current.isEmpty {
                        emptyState
                    } else {
                        agendaList(current)
                    }
                }
                .padding(.horizontal, Space.l)
                .padding(.top, Space.s)
                .padding(.bottom, Space.xxl)
            }
            .background(Color.wren.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { SettingsView() } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(item: $recordingPaymentFor) { bill in
                RecordPaymentView(bill: bill)
            }
            .overlay(alignment: .bottom) {
                if let lastSettled {
                    WrenUndoBanner(title: "Done · \(lastSettled.title)", detail: lastSettled.detail) {
                        undo(lastSettled)
                    }
                }
            }
        }
        .task {
            await scheduler.refreshAuthorizationStatus()
            await ReminderCoordinator.rebuild(context: context, calendar: calendar)
        }
    }

    // MARK: - Header

    private func header(_ agenda: TodayAgenda) -> some View {
        let now = Date()
        return VStack(alignment: .leading, spacing: Space.m) {
            WrenChip(text: "Today")

            VStack(alignment: .leading, spacing: 0) {
                WrenTitle(text: now.formatted(.dateTime.weekday(.wide)))
                WrenTitle(text: now.formatted(.dateTime.day().month(.wide)))
            }

            Text(summaryText(TodaySummary.make(for: agenda, hasAnythingSetUp: hasAnythingSetUp)))
                .font(WrenFont.sentence)
                .lineSpacing(3)
                .foregroundStyle(Color.wren.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The bill total gets the one lime highlight on the screen.
    private func summaryText(_ summary: TodaySummary) -> AttributedString {
        var text = AttributedString(summary.text)
        if let highlight = summary.highlight, let range = text.range(of: highlight) {
            text[range].backgroundColor = theme.highlight
            text[range].foregroundColor = theme.onHighlight
            text[range].font = WrenFont.display(18, relativeTo: .body)
        }
        return text
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

    // MARK: - Tiles

    private func tiles(_ agenda: TodayAgenda) -> some View {
        let binWeek = BinWeekSummary(bins: bins, calendar: calendar)
        let overdueTasks = agenda.overdue.filter { $0.kind == .task }.count
        let billsThisWeek = agenda.allItems.filter { $0.kind == .bill && !$0.isOverdue }.count
        let columns = [GridItem(.flexible(), spacing: Space.l), GridItem(.flexible(), spacing: Space.l)]

        return LazyVGrid(columns: columns, spacing: Space.l) {
            tile(destination: BinsListView()) {
                TodayTile(label: "Bins", value: binWeek.headline, detail: binWeek.detail, swatch: binWeek.swatch)
            }
            tile(destination: BillsListView()) {
                TodayTile(
                    label: "Bills",
                    value: bills.isEmpty ? "None yet" : "\(Money.formatWholeDollars(cents: BillReports.monthlyCommitmentCents(bills.compactMap(\.spec)))) / mo",
                    detail: bills.isEmpty ? "Add one" : "\(billsThisWeek) due this week"
                )
            }
            tile(destination: TasksListView()) {
                TodayTile(
                    label: "Tasks",
                    value: tasks.isEmpty ? "None yet" : "\(tasks.filter(\.isActive).count) active",
                    detail: tasks.isEmpty ? "Add one" : overdueTasks > 0 ? "\(overdueTasks) overdue" : "Nothing overdue",
                    detailColor: overdueTasks > 0 ? .wren.alert : .wren.textSecondary
                )
            }
            tile(destination: ReceiptsListView()) {
                TodayTile(label: "Receipts", value: receiptsValue, detail: receiptsDetail)
            }
        }
    }

    private func tile<Destination: View, Label: View>(
        destination: Destination,
        @ViewBuilder label: () -> Label
    ) -> some View {
        NavigationLink { destination } label: { label() }
            .buttonStyle(.plain)
    }

    private var receiptsValue: String {
        let current = FinancialYear.current(calendar: calendar)
        let total = receipts
            .filter { current.contains($0.date, calendar: calendar) }
            .reduce(0) { $0 + $1.amountCents }
        return receipts.isEmpty ? "None yet" : Money.formatWholeDollars(cents: total)
    }

    private var receiptsDetail: String {
        receipts.isEmpty ? "Scan one" : "\(FinancialYear.current(calendar: calendar).prefixedLabel) so far"
    }

    // MARK: - Agenda

    private func agendaList(_ agenda: TodayAgenda) -> some View {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let later = Dictionary(grouping: agenda.laterThisWeek) { calendar.startOfDay(for: $0.date) }
            .sorted { $0.key < $1.key }

        return VStack(alignment: .leading, spacing: 0) {
            group("Needs doing", items: agenda.overdue, isAlert: true)
            group("Today", items: agenda.today)
            group("Tomorrow · \(tomorrow.formatted(.dateTime.weekday(.abbreviated).day()))", items: agenda.tomorrow)
            ForEach(later, id: \.key) { entry in
                group(entry.key.formatted(.dateTime.weekday(.wide).day()), items: entry.value)
            }
        }
        .padding(.horizontal, Space.m)
        .padding(.bottom, Space.s)
        // The first band sits flush with the top of the box.
        .padding(.top, -Space.m)
        // Bands bleed to the box edge, so the content is clipped to the box's
        // corners before the border goes on.
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .wrenBox()
    }

    /// Each day is a solid band, ink on the box, so the eye lands on the day
    /// before the rows. "Needs doing" is the one red band.
    @ViewBuilder
    private func group(_ title: String, items: [TodayItem], isAlert: Bool = false) -> some View {
        let models = items.compactMap(rowModel)
        if !models.isEmpty {
            WrenSectionLabel(text: title, color: .wren.surface)
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isAlert ? Color.wren.alert : Color.wren.textPrimary)
                .padding(.horizontal, -Space.m)
                .padding(.top, Space.m)

            ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                if index > 0 {
                    Divider().overlay(Color.wren.divider)
                }
                TodayRow(model: model, calendar: calendar)
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
                detail: binDetail(for: item),
                tint: Color(binHex: bin.colorHex),
                action: nil
            )

        case .task:
            guard let task = tasks.first(where: { $0.taskID == item.sourceID }) else { return nil }
            return TodayRowModel(
                item: item,
                title: task.title.isEmpty ? "Untitled task" : task.title,
                detail: overdueDetail(for: item) ?? item.date.formatted(date: .omitted, time: .shortened),
                tint: nil,
                action: { settle(task) }
            )

        case .bill:
            guard let bill = bills.first(where: { $0.billID == item.sourceID }) else { return nil }
            let descriptor = bill.paidBy.isEmpty ? bill.category : bill.paidBy
            let parts = [
                overdueDetail(for: item),
                descriptor.isEmpty ? nil : descriptor,
                item.amountCents.map { Money.format(cents: $0) }
            ]
            return TodayRowModel(
                item: item,
                title: bill.name.isEmpty ? "Untitled bill" : bill.name,
                detail: parts.compactMap { $0 }.joined(separator: " · "),
                tint: nil,
                action: { recordingPaymentFor = bill }
            )
        }
    }

    /// A bin's date is the collection, but the thing to do is the night before.
    /// So the copy names the night, and on the day itself says it's been.
    private func binDetail(for item: TodayItem) -> String {
        let time = item.date.formatted(date: .omitted, time: .shortened)
        switch item.status {
        case .dueToday:
            return item.date <= Date() ? "Collected \(time)" : "Collection at \(time)"
        case .dueTomorrow:
            return "Out tonight, collected \(time)"
        case .upcoming:
            let night = calendar.date(byAdding: .day, value: -1, to: item.date) ?? item.date
            return "Out \(night.formatted(.dateTime.weekday(.wide))) night"
        case .overdue:
            return "Collected \(item.date.formatted(.dateTime.weekday(.abbreviated).day()))"
        }
    }

    private func overdueDetail(for item: TodayItem) -> String? {
        guard case .overdue(let days) = item.status else { return nil }
        switch days {
        case 0: return "Was due at \(item.date.formatted(date: .omitted, time: .shortened))"
        case 1: return "Overdue since yesterday"
        default: return "Overdue by \(days) days"
        }
    }

    // MARK: - Completion

    /// The row disappears the moment it is ticked, so the banner is the only
    /// way back for five seconds.
    private func settle(_ task: RecurringTask) {
        guard let due = TaskStore.complete(task, context: context, calendar: calendar) else { return }
        let settled = SettledTask(taskID: task.taskID, title: task.title, due: due)
        withAnimation(.snappy) { lastSettled = settled }
        Task {
            try? await Task.sleep(for: .seconds(5))
            withAnimation(.snappy) {
                if lastSettled == settled { lastSettled = nil }
            }
        }
    }

    private func undo(_ settled: SettledTask) {
        if let task = tasks.first(where: { $0.taskID == settled.taskID }) {
            TaskStore.undoLastCompletion(task, context: context, calendar: calendar)
        }
        withAnimation(.snappy) { lastSettled = nil }
    }

    private var emptyState: some View {
        WrenCard {
            VStack(alignment: .leading, spacing: Space.s) {
                Text(hasAnythingSetUp ? "Nothing this week" : "Nothing set up yet")
                    .font(WrenFont.title3)
                    .foregroundStyle(Color.wren.textPrimary)
                Text(hasAnythingSetUp
                     ? "No bins, tasks or bills due in the next seven days."
                     : "Add a bin, a task or a bill and it turns up here.")
                    .font(.subheadline)
                    .foregroundStyle(Color.wren.textSecondary)
            }
        }
    }
}
