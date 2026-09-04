import SwiftUI
import SwiftData
import WrenCore

/// Confirms what OCR thinks it read. Parsed values arrive pre-filled but every
/// one is editable, and the alternatives the parser found are offered as chips —
/// suggestions the user confirms, never silent auto-fill.
@MainActor
struct ReceiptEditorView: View {
    /// nil when confirming a fresh scan.
    let receipt: Receipt?
    /// Pages already written to disk, for a fresh scan.
    var pendingFilenames: [String] = []
    var suggestions: ReceiptSuggestions?
    var rawOCRText: String = ""

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var vendor = ""
    @State private var amountCents = 0
    @State private var date = Date()
    @State private var category = ""
    @State private var notes = ""
    @State private var didLoad = false
    @State private var viewingPage: PageSelection?

    private let calendar = Calendar.current
    private let categorySuggestions = ["Work", "Home office", "Tools", "Vehicle", "Education", "Donations"]

    private var isEditing: Bool { receipt != nil }

    private var canSave: Bool { amountCents > 0 }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    WrenTextRow(label: "Vendor", text: $vendor, placeholder: "Bunnings")
                        .wrenRow(first: true)
                    MoneyField(label: "Amount", cents: $amountCents)
                        .wrenRow()
                    WrenDateRow(label: "Date", date: $date, components: .date)
                        .wrenRow(last: true)
                } header: {
                    WrenListHeader(text: "Receipt")
                } footer: {
                    WrenListFooter(text: "Filed under \(FinancialYear.containing(date, calendar: calendar).prefixedLabel).")
                }

                if let suggestions, !isEditing {
                    suggestionSection(suggestions)
                }

                Section {
                    WrenTextRow(label: "Category", text: $category, placeholder: "None")
                        .wrenRow(first: true)
                    if category.isEmpty {
                        WrenSuggestionRow(label: "Common ones", suggestions: categorySuggestions) {
                            category = $0
                        }
                        .wrenRow()
                    }
                    WrenTextRow(label: "Notes", text: $notes, placeholder: "Optional", isMultiline: true)
                        .wrenRow(last: true)
                } header: {
                    WrenListHeader(text: "Category")
                }

                if !currentFilenames.isEmpty {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Space.s) {
                                ForEach(Array(currentFilenames.enumerated()), id: \.element) { offset, filename in
                                    Button {
                                        viewingPage = PageSelection(index: offset)
                                    } label: {
                                        thumbnail(filename)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("View page \(offset + 1)")
                                }
                            }
                            .padding(.vertical, Space.xs)
                        }
                        .wrenRow(first: true, last: true)
                    } header: {
                        WrenListHeader(text: "\(currentFilenames.count) page\(currentFilenames.count == 1 ? "" : "s")")
                    } footer: {
                        WrenListFooter(text: "Tap a page to read it full screen — pinch or double-tap to zoom.")
                    }
                }

                if isEditing {
                    Section {
                        Button("Delete receipt", action: delete)
                            .buttonStyle(WrenDestructiveButtonStyle())
                            .listRowInsets(EdgeInsets(top: Space.l, leading: Space.l, bottom: Space.s, trailing: Space.l))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
            }
            .wrenListStyle()
            .navigationTitle(isEditing ? "Edit receipt" : "Confirm receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                        .font(WrenFont.value)
                        .foregroundStyle(Color.wren.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        WrenToolbarButton(title: "Save", isEnabled: canSave)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                }
            }
            .task { load() }
            .fullScreenCover(item: $viewingPage) { selection in
                ReceiptPageViewer(filenames: currentFilenames, index: selection.index)
            }
        }
    }

    private var currentFilenames: [String] {
        receipt?.imageFilenames ?? pendingFilenames
    }

    @ViewBuilder
    private func thumbnail(_ filename: String) -> some View {
        if let image = ReceiptFileStore.loadImage(filename) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 72, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                        .strokeBorder(Color.wren.textPrimary, lineWidth: Stroke.border)
                )
        } else {
            RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                .fill(Color.wren.accentSoft)
                .frame(width: 72, height: 96)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                        .strokeBorder(Color.wren.textPrimary, lineWidth: Stroke.border)
                )
                .overlay(
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Color.wren.alert)
                )
        }
    }

    /// The parser's alternatives. Shown only for a fresh scan — once saved, the
    /// stored values are the truth and old guesses are noise.
    private func suggestionSection(_ suggestions: ReceiptSuggestions) -> some View {
        let hasAmounts = suggestions.candidateTotals.count > 1
        let hasDates = suggestions.candidateDates.count > 1

        return Section {
            if hasAmounts {
                WrenSuggestionRow(
                    label: "Other amounts found",
                    suggestions: suggestions.candidateTotals.prefix(8).map { Money.format(cents: $0) }
                ) { picked in
                    // Matched back to the original cents rather than reparsed,
                    // so a currency symbol or separator can never lose money.
                    if let cents = suggestions.candidateTotals.first(where: { Money.format(cents: $0) == picked }) {
                        amountCents = cents
                    }
                }
                .wrenRow(first: true, last: !hasDates)
            }
            if hasDates {
                WrenSuggestionRow(
                    label: "Other dates found",
                    suggestions: suggestions.candidateDates.prefix(6).map { $0.formatted(.dateTime.day().month().year()) }
                ) { picked in
                    if let match = suggestions.candidateDates.first(where: {
                        $0.formatted(.dateTime.day().month().year()) == picked
                    }) {
                        date = match
                    }
                }
                .wrenRow(first: !hasAmounts, last: true)
            }
            if !hasAmounts, !hasDates {
                Text("Nothing else was read from the scan.")
                    .font(.subheadline)
                    .foregroundStyle(Color.wren.textSecondary)
                    .padding(.vertical, Space.xs)
                    .wrenRow(first: true, last: true)
            }
        } header: {
            WrenListHeader(text: "From the scan")
        } footer: {
            WrenListFooter(text: suggestions.isEmpty
                           ? "Nothing could be read from the scan — enter the details by hand."
                           : "Read from the receipt, so check them. Tap an alternative to use it instead.")
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true

        guard let receipt else {
            vendor = suggestions?.vendor ?? ""
            amountCents = suggestions?.totalCents ?? 0
            date = suggestions?.date ?? Date()
            return
        }

        vendor = receipt.vendor
        amountCents = receipt.amountCents
        date = receipt.date
        category = receipt.category
        notes = receipt.notes
    }

    private func save() {
        if let receipt {
            receipt.vendor = vendor.trimmingCharacters(in: .whitespaces)
            receipt.amountCents = amountCents
            receipt.date = date
            receipt.category = category.trimmingCharacters(in: .whitespaces)
            receipt.notes = notes
            Logger.shared.info("receipts", "updated receipt '\(receipt.displayVendor)'")
        } else {
            let created = Receipt(
                vendor: vendor.trimmingCharacters(in: .whitespaces),
                amountCents: amountCents,
                date: date,
                category: category.trimmingCharacters(in: .whitespaces),
                notes: notes,
                rawOCRText: rawOCRText,
                imageFilenames: pendingFilenames
            )
            context.insert(created)
            Logger.shared.info(
                "receipts",
                "saved receipt '\(created.displayVendor)' \(Money.plainFormat(cents: amountCents))"
                    + " in \(created.financialYear(calendar: calendar).prefixedLabel)"
            )
        }

        do {
            try context.save()
        } catch {
            Logger.shared.error("receipts", "save failed: \(error.localizedDescription)")
        }
        dismiss()
    }

    /// Abandoning a fresh scan has to clean up the pages already written, or
    /// they linger on disk with nothing referencing them.
    private func cancel() {
        if receipt == nil, !pendingFilenames.isEmpty {
            Logger.shared.info("receipts", "discarded \(pendingFilenames.count) unsaved page(s)")
            ReceiptFileStore.delete(pendingFilenames)
        }
        dismiss()
    }

    private func delete() {
        guard let receipt else { return }
        let filenames = receipt.imageFilenames
        Logger.shared.info("receipts", "deleted receipt '\(receipt.displayVendor)'")
        context.delete(receipt)
        do {
            try context.save()
            // Files go only after the row is gone, so a failure leaves an
            // orphaned file rather than a receipt with missing pages.
            ReceiptFileStore.delete(filenames)
        } catch {
            Logger.shared.error("receipts", "delete failed: \(error.localizedDescription)")
        }
        dismiss()
    }
}

/// `fullScreenCover(item:)` needs an Identifiable, and a bare Int isn't one.
private struct PageSelection: Identifiable {
    let index: Int
    var id: Int { index }
}
