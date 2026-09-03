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

    private let calendar = Calendar.current
    private let categorySuggestions = ["Work", "Home office", "Tools", "Vehicle", "Education", "Donations"]

    private var isEditing: Bool { receipt != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Vendor", text: $vendor)
                    MoneyField(label: "Amount", cents: $amountCents)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                } header: {
                    Text("Receipt")
                } footer: {
                    Text("Filed under \(FinancialYear.containing(date, calendar: calendar).prefixedLabel).")
                }

                if let suggestions, !isEditing {
                    suggestionSection(suggestions)
                }

                Section("Category") {
                    TextField("Category", text: $category)
                    if category.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Space.s) {
                                ForEach(categorySuggestions, id: \.self) { suggestion in
                                    chip(suggestion) { category = suggestion }
                                }
                            }
                        }
                    }
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                if !currentFilenames.isEmpty {
                    Section("\(currentFilenames.count) page\(currentFilenames.count == 1 ? "" : "s")") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Space.s) {
                                ForEach(currentFilenames, id: \.self) { filename in
                                    if let image = ReceiptFileStore.loadImage(filename) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 72, height: 96)
                                            .clipShape(RoundedRectangle(cornerRadius: Radius.chip))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: Radius.chip)
                                                    .strokeBorder(Color.wren.divider, lineWidth: 1)
                                            )
                                    }
                                }
                            }
                        }
                    }
                }

                if isEditing {
                    Section {
                        Button("Delete receipt", role: .destructive, action: delete)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.wren.background)
            .navigationTitle(isEditing ? "Edit receipt" : "Confirm receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(amountCents == 0)
                }
            }
            .task { load() }
        }
    }

    private var currentFilenames: [String] {
        receipt?.imageFilenames ?? pendingFilenames
    }

    /// The parser's alternatives. Shown only for a fresh scan — once saved, the
    /// stored values are the truth and old guesses are noise.
    private func suggestionSection(_ suggestions: ReceiptSuggestions) -> some View {
        Section {
            if suggestions.candidateTotals.count > 1 {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Other amounts found")
                        .font(.caption)
                        .foregroundStyle(Color.wren.textSecondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Space.s) {
                            ForEach(suggestions.candidateTotals.prefix(8), id: \.self) { cents in
                                chip(Money.format(cents: cents)) { amountCents = cents }
                            }
                        }
                    }
                }
                .padding(.vertical, Space.xs)
            }

            if suggestions.candidateDates.count > 1 {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Other dates found")
                        .font(.caption)
                        .foregroundStyle(Color.wren.textSecondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Space.s) {
                            ForEach(suggestions.candidateDates.prefix(6), id: \.self) { candidate in
                                chip(candidate.formatted(.dateTime.day().month().year())) { date = candidate }
                            }
                        }
                    }
                }
                .padding(.vertical, Space.xs)
            }
        } header: {
            Text("From the scan")
        } footer: {
            Text(suggestions.isEmpty
                 ? "Nothing could be read from the scan — enter the details by hand."
                 : "Read from the receipt, so check them. Tap an alternative to use it instead.")
        }
    }

    private func chip(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(Color.wren.accent)
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs)
            .background(Color.wren.accentSoft, in: RoundedRectangle(cornerRadius: Radius.chip))
            .buttonStyle(.plain)
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
