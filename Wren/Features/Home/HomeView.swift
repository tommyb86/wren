import SwiftUI
import SwiftData
import WrenCore

@MainActor
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BinCollection.sortOrder) private var bins: [BinCollection]
    @StateObject private var scheduler = NotificationScheduler.shared

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    header

                    NavigationLink {
                        BinsListView()
                    } label: {
                        BinWeekCard(bins: bins, calendar: calendar)
                    }
                    .buttonStyle(.plain)

                    if scheduler.authorizationStatus == .denied && !bins.isEmpty {
                        permissionWarning
                    }

                    upcoming

                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        WrenCard {
                            HStack {
                                VStack(alignment: .leading, spacing: Space.xs) {
                                    Text("Diagnostics")
                                        .font(.headline)
                                        .foregroundStyle(Color.wren.textPrimary)
                                    Text("\(scheduler.pending.count) reminder\(scheduler.pending.count == 1 ? "" : "s") scheduled")
                                        .font(.subheadline)
                                        .monospacedDigit()
                                        .foregroundStyle(Color.wren.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(Color.wren.textSecondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(Space.l)
            }
            .background(Color.wren.background)
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await scheduler.refreshAuthorizationStatus()
            await scheduler.rebuild(bins: bins, calendar: calendar)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            WrenTitle(text: "Wren")
            Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.footnote)
                .foregroundStyle(Color.wren.textSecondary)
        }
        .padding(.top, Space.s)
    }

    /// Terracotta earns its keep here: without permission the app silently does
    /// nothing useful, which is worth shouting about.
    private var permissionWarning: some View {
        WrenCard {
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Reminders are switched off")
                    .font(.headline)
                    .foregroundStyle(Color.wren.alert)
                Text("Wren can't notify you about bin nights until notifications are allowed in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(Color.wren.textSecondary)
            }
        }
    }

    /// The next fortnight, so "is it recycling next week?" is answerable without
    /// opening anything.
    private var upcoming: some View {
        let horizon = calendar.date(byAdding: .day, value: 14, to: Date()) ?? Date()
        let window = BinCycle.window(
            schedules: bins.filter(\.isActive).compactMap(\.binSchedule),
            from: Date(),
            to: horizon,
            calendar: calendar
        )

        return Group {
            if !window.nights.isEmpty {
                VStack(alignment: .leading, spacing: Space.m) {
                    Text("Next fortnight")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.wren.textSecondary)

                    VStack(spacing: 0) {
                        ForEach(Array(window.nights.enumerated()), id: \.element) { index, night in
                            nightRow(night, dues: window.due.filter { $0.date == night })
                            if index < window.nights.count - 1 {
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
    }

    private func nightRow(_ night: Date, dues: [BinDue]) -> some View {
        HStack(spacing: Space.m) {
            HStack(spacing: Space.xs) {
                ForEach(dues) { due in
                    if let bin = bins.first(where: { $0.binID == due.binID }) {
                        Circle()
                            .fill(Color(binHex: bin.colorHex))
                            .frame(width: 10, height: 10)
                    }
                }
            }
            .frame(width: 44, alignment: .leading)

            Text(night.formatted(.dateTime.weekday(.abbreviated).day().month()))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Color.wren.textPrimary)

            Spacer()

            Text(dues.compactMap { due in bins.first { $0.binID == due.binID }?.name }.joined(separator: " + "))
                .font(.caption)
                .foregroundStyle(Color.wren.textSecondary)
                .lineLimit(1)
        }
        .padding(Space.m)
    }
}
