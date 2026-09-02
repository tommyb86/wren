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
                    Image(systemName: "plus")
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
        List {
            ForEach(bins) { bin in
                Button {
                    editing = bin
                } label: {
                    row(bin)
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: delete)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func row(_ bin: BinCollection) -> some View {
        HStack(spacing: Space.m) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(binHex: bin.colorHex))
                .frame(width: 6, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(bin.name.isEmpty ? "Untitled bin" : bin.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.wren.textPrimary)
                Text(bin.schedule?.summary(calendar: calendar) ?? "No schedule")
                    .font(.caption)
                    .foregroundStyle(Color.wren.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if !bin.isActive {
                    Text("Paused")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.wren.textSecondary)
                } else if let next = bin.nextCollection(calendar: calendar) {
                    Text(next.formatted(.dateTime.weekday(.abbreviated).day().month()))
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.wren.textPrimary)
                    Text(next.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
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
            Image(systemName: "trash")
                .font(.system(size: 32))
                .foregroundStyle(Color.wren.textSecondary)
            Text("No bins yet")
                .font(.system(.title3, design: .serif))
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

