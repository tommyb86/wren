import SwiftUI
import SwiftData
import WrenCore

/// The week ahead from his personal calendar: his timetable and the events he
/// is actually in, grouped by day. Where a notice turns out to be about the same
/// thing, the event carries a link to it — so the assembly's time comes from the
/// calendar and its parking note comes from the news, on one row.
///
/// Built as a pushed `ScrollView` like `SchoolNoticeView`. Note where the
/// correlation runs: once, in `.task`, into state. It extracts dates from every
/// candidate notice, so doing it inside `body` would be O(events x notices) of
/// regex on the main thread on every single view update.
@MainActor
struct SchoolWeekView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.wrenTheme) private var theme

    @Query(sort: \SchoolEvent.start) private var events: [SchoolEvent]
    @Query(sort: \SchoolNotice.published, order: .reverse) private var notices: [SchoolNotice]

    /// Event `uid` to notice `guid`, for events confidently about a notice.
    @State private var links: [String: String] = [:]

    /// How far ahead the view looks. Three weeks is a term's worth of planning
    /// without turning into a year planner.
    private let horizonDays = 21

    var body: some View {
        let days = self.days
        return ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                if days.isEmpty {
                    emptyState
                } else {
                    ForEach(days, id: \.date) { day in
                        daySection(day)
                    }
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.m)
            .padding(.bottom, Space.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.wren.background)
        .navigationTitle("Week ahead")
        .navigationBarTitleDisplayMode(.inline)
        .task { rebuildLinks() }
        .refreshable {
            await SchoolStore.refresh(context: context)
            rebuildLinks()
        }
    }

    // MARK: - Grouping

    private var upcoming: [SchoolEvent] {
        let calendar = Calendar.current
        let floor = calendar.startOfDay(for: Date())
        let ceiling = calendar.date(byAdding: .day, value: horizonDays, to: floor) ?? .distantFuture
        return events.filter { $0.finish >= floor && $0.start < ceiling }
    }

    private var days: [(date: Date, events: [SchoolEvent])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: upcoming) { calendar.startOfDay(for: $0.start) }
        return grouped.keys.sorted().map { key in
            (key, (grouped[key] ?? []).sorted { $0.start < $1.start })
        }
    }

    // MARK: - Rows

    private func daySection(_ day: (date: Date, events: [SchoolEvent])) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(dayLabel(day.date))
                .font(WrenFont.caption)
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Color.wren.textSecondary)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(day.events.enumerated()), id: \.element.uid) { index, event in
                    if index > 0 {
                        Divider().overlay(Color.wren.divider)
                    }
                    eventRow(event)
                }
            }
            .padding(.horizontal, Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .wrenBox()
        }
    }

    private func eventRow(_ event: SchoolEvent) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            Text(timeLabel(event))
                .font(WrenFont.value)
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(Color.wren.textPrimary)
                .frame(width: 66, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title.isEmpty ? "Untitled event" : event.title)
                    .font(WrenFont.heading)
                    .foregroundStyle(Color.wren.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if !event.location.isEmpty {
                    Text(event.location)
                        .font(WrenFont.detail)
                        .foregroundStyle(Color.wren.textSecondary)
                }

                if let notice = linkedNotice(event) {
                    NavigationLink {
                        SchoolNoticeView(notice: notice)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            WrenLidSwatch(color: theme.highlight, size: 10)
                            Text(notice.title.isEmpty ? "There's a notice about this" : notice.title)
                                .font(WrenFont.detail)
                                .foregroundStyle(Color.wren.textSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.s)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Nothing in the next three weeks")
                .font(WrenFont.title3)
                .foregroundStyle(Color.wren.textPrimary)
            Text("Pull down to refresh. If it stays empty, check the calendar address in School settings.")
                .font(.subheadline)
                .foregroundStyle(Color.wren.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Space.xl)
    }

    // MARK: - Correlation

    /// Links events to the notice about the same thing. Deliberately bounded on
    /// both sides, and only accepts a confident (two-signal) match — a wrong
    /// link is worse than no link, since it would send the reader to the wrong
    /// notice.
    private func rebuildLinks() {
        let candidates = notices.prefix(40).map(\.feedItem)
        guard !candidates.isEmpty else { links = [:]; return }

        var found: [String: String] = [:]
        for event in upcoming.prefix(40) {
            let match = SchoolCorrelation.correlate(
                event: event.calendarEvent,
                notices: Array(candidates),
                calendar: Calendar.current
            )
            if let match, match.isMerge {
                found[event.uid] = match.noticeGUID
            }
        }
        links = found
    }

    private func linkedNotice(_ event: SchoolEvent) -> SchoolNotice? {
        guard let guid = links[event.uid] else { return nil }
        return notices.first { $0.guid == guid }
    }

    // MARK: - Labels

    private func timeLabel(_ event: SchoolEvent) -> String {
        event.allDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened)
    }

    private func dayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }
}
