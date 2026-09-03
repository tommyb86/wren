import SwiftUI
import UIKit
import SwiftData
import UserNotifications

/// First-class feature, not a debug afterthought. When something misbehaves on
/// the device, this screen is the only window in.
@MainActor
struct DiagnosticsView: View {
    @Environment(\.modelContext) private var context
    @StateObject private var logger = Logger.shared
    @StateObject private var scheduler = NotificationScheduler.shared

    @State private var levelFilter: Logger.Level?
    @State private var binCount = 0
    @State private var taskCount = 0
    @State private var completionCount = 0
    @State private var billCount = 0
    @State private var paymentCount = 0
    @State private var receiptCount = 0
    @State private var receiptFileCount = 0
    @State private var receiptBytes: Int64 = 0
    @State private var orphanedFileCount = 0
    @State private var showingExport = false

    var body: some View {
        List {
            environmentSection
            notificationSection
            storageSection
            receiptFilesSection
            logSection
            colophon
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.wren.background)
        .navigationTitle("Diagnostics")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Export log") { showingExport = true }
                    Button("Clear log", role: .destructive) { logger.clear() }
                    Button("Cancel all notifications", role: .destructive) {
                        Task { await scheduler.cancelAll() }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingExport) {
            ShareSheet(text: logger.exportText())
        }
        .task {
            await scheduler.refreshAuthorizationStatus()
            await scheduler.refreshPending()
            refreshCounts()
        }
    }

    // MARK: - Sections

    private var environmentSection: some View {
        Section("Build") {
            row("Version", BuildInfo.version)
            row("Build", BuildInfo.build)
            row("Commit", BuildInfo.gitSHA)
            row("Bundle ID", BuildInfo.bundleID)
            row("iOS", ProcessInfo.processInfo.operatingSystemVersionString)
            // Font.custom falls back to the system face without a word, so a
            // wrong PostScript name or a missing plist entry only shows here.
            row("Display font", WrenFont.isInstalled ? "\(WrenFont.family) installed" : "\(WrenFont.family) missing")
        }
    }

    private var notificationSection: some View {
        Section {
            row("Authorisation", scheduler.authorizationStatus.wrenLabel)
            row("Pending", "\(scheduler.pending.count) / \(NotificationScheduler.pendingLimit)")
            row("Budget", "\(NotificationScheduler.requestBudget) over \(NotificationScheduler.horizonDays)d")
            if let lastRebuild = scheduler.lastRebuild {
                row("Last rebuild", lastRebuild.formatted(date: .omitted, time: .standard))
            }
            if scheduler.droppedAtCap > 0 {
                row("Dropped at cap", "\(scheduler.droppedAtCap)")
            }

            Button("Rebuild reminders now") {
                Task { await rebuild() }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.wren.accent)

            // Kept from Phase 0: the quickest way to confirm notifications still
            // work after SideStore re-signs the build every seven days.
            Button("Test notification (60s)") {
                Task { await scheduler.scheduleTestNotification() }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.wren.accent)

            if scheduler.pending.isEmpty {
                Text("Nothing scheduled.")
                    .font(.subheadline)
                    .foregroundStyle(Color.wren.textSecondary)
            } else {
                ForEach(scheduler.pending, id: \.identifier) { request in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(request.identifier)
                            .font(.caption.monospaced())
                            .foregroundStyle(Color.wren.textPrimary)
                        Text(fireDescription(for: request))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Color.wren.textSecondary)
                    }
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("iOS drops pending local notifications past 64. The set is rebuilt on foreground.")
        }
    }

    private var storageSection: some View {
        Section("SwiftData") {
            row("BinCollection", "\(binCount) rows")
            row("RecurringTask", "\(taskCount) rows")
            row("TaskCompletion", "\(completionCount) rows")
            row("Bill", "\(billCount) rows")
            row("BillPayment", "\(paymentCount) rows")
            row("Receipt", "\(receiptCount) rows")
        }
    }

    private var receiptFilesSection: some View {
        Section {
            row("Files", "\(receiptFileCount)")
            row("On disk", "\(receiptBytes / 1024)KB")
            if orphanedFileCount > 0 {
                // Surfaced rather than swept up automatically: deleting a
                // user's files on a hunch is worse than a few stray kilobytes,
                // and an orphan usually means a delete half-failed, which is
                // worth knowing about.
                row("Unreferenced", "\(orphanedFileCount)")
            }
        } header: {
            Text("Receipt images")
        } footer: {
            Text("JPEGs in Documents/receipts, referenced by filename from SwiftData rather than stored as blobs.")
        }
    }

    private var logSection: some View {
        Section {
            Picker("Level", selection: $levelFilter) {
                Text("All").tag(Logger.Level?.none)
                ForEach(Logger.Level.allCases) { level in
                    Text(level.rawValue.capitalized).tag(Logger.Level?.some(level))
                }
            }
            .pickerStyle(.segmented)

            if filteredEntries.isEmpty {
                Text("No entries at this level.")
                    .font(.subheadline)
                    .foregroundStyle(Color.wren.textSecondary)
            } else {
                ForEach(filteredEntries) { entry in
                    HStack(alignment: .top, spacing: Space.s) {
                        Image(systemName: entry.level.symbol)
                            .font(.caption)
                            .foregroundStyle(entry.level == .error || entry.level == .warn
                                             ? Color.wren.alert : Color.wren.textSecondary)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.message)
                                .font(.caption)
                                .foregroundStyle(Color.wren.textPrimary)
                            Text("\(Logger.Entry.stamp.string(from: entry.date)) · \(entry.category)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(Color.wren.textSecondary)
                        }
                    }
                }
            }
        } header: {
            Text("Log — \(logger.entries.count) entries, newest first")
        }
    }

    /// The last thing you see on the way out — a printer's colophon rather than
    /// a splash. Also the fastest way to read back exactly which build is on the
    /// phone when something looks wrong.
    private var colophon: some View {
        Section {
            VStack(spacing: Space.s) {
                WrenMark(size: 52)
                Text("Wren \(BuildInfo.version)")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.wren.textPrimary)
                Text("build \(BuildInfo.build) · \(BuildInfo.gitSHA)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(Color.wren.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.m)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Helpers

    /// Newest first.
    private var filteredEntries: [Logger.Entry] {
        let all = logger.entries.reversed()
        guard let levelFilter else { return Array(all) }
        return all.filter { $0.level == levelFilter }
    }

    private func fireDescription(for request: UNNotificationRequest) -> String {
        guard let date = request.wrenFireDate else { return "no fire date" }
        let delta = Int(date.timeIntervalSinceNow)
        let when = date.formatted(date: .abbreviated, time: .standard)
        return delta >= 0 ? "\(when) · in \(delta)s" : "\(when) · \(-delta)s ago"
    }

    private func refreshCounts() {
        do {
            binCount = try context.fetchCount(FetchDescriptor<BinCollection>())
            taskCount = try context.fetchCount(FetchDescriptor<RecurringTask>())
            completionCount = try context.fetchCount(FetchDescriptor<TaskCompletion>())
            billCount = try context.fetchCount(FetchDescriptor<Bill>())
            paymentCount = try context.fetchCount(FetchDescriptor<BillPayment>())
            receiptCount = try context.fetchCount(FetchDescriptor<Receipt>())

            // Cross-checks the filesystem against what the store references, so
            // a half-failed delete is visible rather than silently leaking.
            let referenced = Set(try context.fetch(FetchDescriptor<Receipt>()).flatMap(\.imageFilenames))
            receiptFileCount = ReceiptFileStore.fileCount()
            receiptBytes = ReceiptFileStore.totalBytes()
            orphanedFileCount = ReceiptFileStore.orphanedFiles(referenced: referenced).count
        } catch {
            Logger.shared.error("diagnostics", "row count failed: \(error.localizedDescription)")
        }
    }

    private func rebuild() async {
        await ReminderCoordinator.rebuild(context: context)
        refreshCounts()
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.wren.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Color.wren.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// The only route off the device for a log file.
struct ShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
