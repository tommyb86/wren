import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @StateObject private var scheduler = NotificationScheduler.shared
    @Query private var probes: [PipelineProbe]

    @State private var lastScheduledAt: Date?

    private let log = Logger.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    header

                    WrenCard {
                        VStack(alignment: .leading, spacing: Space.m) {
                            Text("Pipeline test")
                                .font(.headline)
                                .foregroundStyle(Color.wren.textPrimary)
                            Text("Schedules a local notification 60 seconds out. Lock the phone and wait — this is the one thing Phase 0 has to prove.")
                                .font(.subheadline)
                                .foregroundStyle(Color.wren.textSecondary)

                            Button("Test notification (60s)") {
                                Task {
                                    await scheduler.scheduleTestNotification()
                                    lastScheduledAt = Date()
                                }
                            }
                            .buttonStyle(WrenPrimaryButtonStyle())

                            HStack(spacing: Space.s) {
                                WrenChip(text: scheduler.authorizationStatus.wrenLabel)
                                WrenChip(text: "\(scheduler.pending.count) pending")
                                if let lastScheduledAt {
                                    WrenChip(text: "tapped \(lastScheduledAt.formatted(date: .omitted, time: .shortened))")
                                }
                            }
                        }
                    }

                    WrenCard {
                        VStack(alignment: .leading, spacing: Space.m) {
                            Text("Storage probe")
                                .font(.headline)
                                .foregroundStyle(Color.wren.textPrimary)
                            Text("\(probes.count) row\(probes.count == 1 ? "" : "s") written. Survives relaunch if SwiftData is healthy.")
                                .font(.subheadline)
                                .foregroundStyle(Color.wren.textSecondary)

                            Button("Write a row") { writeProbe() }
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.wren.accent)
                        }
                    }

                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        WrenCard {
                            HStack {
                                VStack(alignment: .leading, spacing: Space.xs) {
                                    Text("Diagnostics")
                                        .font(.headline)
                                        .foregroundStyle(Color.wren.textPrimary)
                                    Text("Logs, pending notifications, build info")
                                        .font(.subheadline)
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
            await scheduler.refreshPending()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            WrenTitle(text: "Wren")
            Text(BuildInfo.summary)
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Color.wren.textSecondary)
        }
        .padding(.top, Space.s)
    }

    private func writeProbe() {
        let probe = PipelineProbe(note: "tapped at \(Date().formatted(date: .abbreviated, time: .standard))")
        context.insert(probe)
        do {
            try context.save()
            log.info("storage", "probe saved — \(probes.count + 1) rows")
        } catch {
            log.error("storage", "probe save failed: \(error.localizedDescription)")
        }
    }
}
