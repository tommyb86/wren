import SwiftUI
import SwiftData
import WrenCore

@MainActor
struct BinsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BinCollection.sortOrder) private var bins: [BinCollection]

    @State private var editing: BinCollection?
    @State private var isAdding = false

    private let calendar = Calendar.current

    var body: some View {
        Group {
            if bins.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(Color.wren.background)
        .navigationTitle("Bins")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAdding = true
                } label: {
                    WrenToolbarIcon(systemName: "plus")
                }
                .accessibilityLabel("Add bin")
            }
        }
        .sheet(isPresented: $isAdding) {
            BinEditorView(bin: nil, existingBinCount: bins.count)
        }
        .sheet(item: $editing) { bin in
            BinEditorView(bin: bin, existingBinCount: bins.count)
        }
    }

    private var list: some View {
        let active = bins.filter(\.isActive).count
        return List {
            Section {
                ForEach(Array(bins.enumerated()), id: \.element.binID) { index, bin in
                    Button {
                        editing = bin
                    } label: {
                        row(bin)
                    }
                    .buttonStyle(.plain)
                    .wrenRow(first: index == 0, last: index == bins.count - 1)
                }
                .onDelete(perform: delete)
            } header: {
                WrenListHeader(text: "Bins", trailing: "\(active) active")
            }
        }
        .wrenListStyle()
    }

    private func row(_ bin: BinCollection) -> some View {
        HStack(spacing: Space.m) {
            WrenLidSwatch(color: Color(binHex: bin.colorHex))

            VStack(alignment: .leading, spacing: 2) {
                Text(bin.name.isEmpty ? "Untitled bin" : bin.name)
                    .font(WrenFont.heading)
                    .foregroundStyle(bin.isActive ? Color.wren.textPrimary : Color.wren.textSecondary)
                Text(bin.schedule?.summary(calendar: calendar) ?? "No schedule")
                    .font(WrenFont.detail)
                    .foregroundStyle(Color.wren.textSecondary)
            }

            Spacer()

            if !bin.isActive {
                WrenChip(text: "Paused", tint: .wren.textSecondary, fill: .wren.surface)
            } else if let next = bin.nextCollection(calendar: calendar) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(next.formatted(.dateTime.weekday(.abbreviated).day().month()))
                        .font(WrenFont.value)
                        .monospacedDigit()
                        .foregroundStyle(Color.wren.textPrimary)
                    Text(next.formatted(date: .omitted, time: .shortened))
                        .font(.caption2.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.wren.textSecondary)
                }
            }
        }
        .padding(.vertical, Space.xs)
        .contentShape(.rect)
    }

    private var emptyState: some View {
        VStack(spacing: Space.m) {
            WrenMark(size: 64)
                .padding(.bottom, Space.xs)
            Text("No bins yet")
                .font(WrenFont.title3)
                .foregroundStyle(Color.wren.textPrimary)
            Text("Most councils run general waste weekly and recycling fortnightly. Add one bin per lid.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.wren.textSecondary)
            Button("Add your first bin") { isAdding = true }
                .buttonStyle(WrenPrimaryButtonStyle())
                .padding(.top, Space.s)
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            Logger.shared.info("bins", "deleted '\(bins[index].name)'")
            context.delete(bins[index])
        }
        do {
            try context.save()
        } catch {
            Logger.shared.error("bins", "delete failed: \(error.localizedDescription)")
        }
        Task { await ReminderCoordinator.rebuild(context: context, calendar: calendar) }
    }
}
