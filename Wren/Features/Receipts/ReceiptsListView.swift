import SwiftUI
import SwiftData
import WrenCore

/// Receipts grouped by Australian financial year, because that is the only
/// grouping that matters at tax time.
@MainActor
struct ReceiptsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]

    @State private var isScanning = false
    @State private var pendingScan: PendingScan?
    @State private var isProcessing = false
    @State private var editing: Receipt?
    @State private var selectedYear: FinancialYear?
    @State private var exportURL: URL?
    @State private var exportText: String?
    @State private var scannerUnavailable = false

    private let calendar = Calendar.current

    /// A scan that has been written to disk and read, waiting to be confirmed.
    private struct PendingScan: Identifiable {
        let id = UUID()
        let filenames: [String]
        let suggestions: ReceiptSuggestions
        let rawText: String
    }

    private var years: [FinancialYear] {
        FinancialYear.spanning(receipts.map(\.date), calendar: calendar)
    }

    private var visibleReceipts: [Receipt] {
        guard let selectedYear else { return receipts }
        return receipts.filter { selectedYear.contains($0.date, calendar: calendar) }
    }

    var body: some View {
        Group {
            if receipts.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(Color.wren.background)
        .navigationTitle("Receipts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: startScan) {
                    Image(systemName: "doc.viewfinder")
                }
                .accessibilityLabel("Scan a receipt")
                .disabled(isProcessing)
            }
        }
        .fullScreenCover(isPresented: $isScanning) {
            DocumentScanner(
                onFinish: { images in
                    isScanning = false
                    Task { await process(images) }
                },
                onCancel: { isScanning = false }
            )
            .ignoresSafeArea()
        }
        .sheet(item: $pendingScan) { scan in
            ReceiptEditorView(
                receipt: nil,
                pendingFilenames: scan.filenames,
                suggestions: scan.suggestions,
                rawOCRText: scan.rawText
            )
        }
        .sheet(item: $editing) { receipt in
            ReceiptEditorView(receipt: receipt)
        }
        .sheet(item: Binding(
            get: { exportText.map(TextPayload.init) },
            set: { exportText = $0?.text }
        )) { payload in
            ShareSheet(text: payload.text)
        }
        .sheet(item: Binding(
            get: { exportURL.map(URLPayload.init) },
            set: { exportURL = $0?.url }
        )) { payload in
            ShareFileSheet(url: payload.url)
        }
        .alert("No camera available", isPresented: $scannerUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This device can't scan documents.")
        }
        .overlay {
            if isProcessing {
                processingOverlay
            }
        }
    }

    // MARK: - List

    private var list: some View {
        List {
            summarySection

            ForEach(displayedYears) { year in
                let inYear = visibleReceipts.filter { year.contains($0.date, calendar: calendar) }
                if !inYear.isEmpty {
                    Section {
                        ForEach(inYear) { receipt in
                            Button { editing = receipt } label: { row(receipt) }
                                .buttonStyle(.plain)
                        }
                    } header: {
                        HStack {
                            Text(year.prefixedLabel)
                            Spacer()
                            Text(Money.format(cents: total(of: inYear)))
                                .monospacedDigit()
                        }
                    } footer: {
                        exportFooter(year: year, receipts: inYear)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var displayedYears: [FinancialYear] {
        selectedYear.map { [$0] } ?? years
    }

    private var summarySection: some View {
        Section {
            Picker("Financial year", selection: $selectedYear) {
                Text("All years").tag(FinancialYear?.none)
                ForEach(years) { year in
                    Text(year.label).tag(FinancialYear?.some(year))
                }
            }

            HStack {
                Text("\(visibleReceipts.count) receipt\(visibleReceipts.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(Color.wren.textSecondary)
                Spacer()
                Text(Money.format(cents: total(of: visibleReceipts)))
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.wren.textPrimary)
            }
        }
    }

    private func row(_ receipt: Receipt) -> some View {
        HStack(spacing: Space.m) {
            if let first = receipt.imageFilenames.first, let image = ReceiptFileStore.loadImage(first) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 34, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.wren.divider, lineWidth: 1))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.wren.accentSoft)
                    .frame(width: 34, height: 44)
                    .overlay(
                        Image(systemName: "doc.text")
                            .font(.caption)
                            .foregroundStyle(Color.wren.accent)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(receipt.displayVendor)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.wren.textPrimary)
                Text(subtitle(receipt))
                    .font(.caption)
                    .foregroundStyle(Color.wren.textSecondary)
            }

            Spacer()

            Text(Money.format(cents: receipt.amountCents))
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(Color.wren.textPrimary)
        }
        .padding(.vertical, Space.xs)
        .contentShape(.rect)
    }

    private func subtitle(_ receipt: Receipt) -> String {
        var parts = [receipt.date.formatted(.dateTime.day().month().year())]
        if !receipt.category.isEmpty { parts.append(receipt.category) }
        if receipt.pageCount > 1 { parts.append("\(receipt.pageCount) pages") }
        return parts.joined(separator: " · ")
    }

    private func exportFooter(year: FinancialYear, receipts: [Receipt]) -> some View {
        HStack(spacing: Space.m) {
            Button("Export CSV") {
                exportText = ReceiptCSV.rows(receipts, calendar: calendar)
            }
            Button("Export images") {
                let filenames = receipts.flatMap(\.imageFilenames)
                guard !filenames.isEmpty else {
                    Logger.shared.warn("receipts", "no images to export for \(year.label)")
                    return
                }
                exportURL = ReceiptFileStore.zip(
                    filenames: filenames,
                    archiveName: "Wren-receipts-\(year.label.replacingOccurrences(of: "–", with: "-"))"
                )
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(Color.wren.accent)
        .padding(.top, Space.xs)
    }

    private var emptyState: some View {
        VStack(spacing: Space.m) {
            WrenMark(size: 64)
                .padding(.bottom, Space.xs)
            Text("No receipts yet")
                .font(.system(.title3, design: .serif))
                .foregroundStyle(Color.wren.textPrimary)
            Text("Scan a receipt and Wren reads the vendor, amount and date for you to confirm, then files it by financial year.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.wren.textSecondary)
            Button("Scan a receipt", action: startScan)
                .buttonStyle(WrenPrimaryButtonStyle())
                .padding(.top, Space.s)
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var processingOverlay: some View {
        VStack(spacing: Space.m) {
            ProgressView()
            Text("Reading the receipt…")
                .font(.subheadline)
                .foregroundStyle(Color.wren.textSecondary)
        }
        .padding(Space.xl)
        .background(Color.wren.surface, in: RoundedRectangle(cornerRadius: Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(Color.wren.divider, lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func startScan() {
        guard DocumentScanner.isAvailable else {
            scannerUnavailable = true
            Logger.shared.warn("receipts", "document scanning unsupported on this device")
            return
        }
        isScanning = true
    }

    /// Pages are written to disk first, then read. If the user abandons the
    /// confirmation sheet, the editor cleans those files up.
    private func process(_ images: [UIImage]) async {
        guard !images.isEmpty else { return }
        isProcessing = true

        let filenames = ReceiptFileStore.save(images)
        let text = await ReceiptOCR.recognizeText(in: images)
        let suggestions = ReceiptParser.parse(text, calendar: calendar)

        Logger.shared.info(
            "receipts",
            "parsed vendor=\(suggestions.vendor ?? "nil")"
                + " total=\(suggestions.totalCents.map { Money.plainFormat(cents: $0) } ?? "nil")"
                + " date=\(suggestions.date?.formatted(date: .numeric, time: .omitted) ?? "nil")"
        )

        isProcessing = false
        pendingScan = PendingScan(filenames: filenames, suggestions: suggestions, rawText: text)
    }

    private func total(of receipts: [Receipt]) -> Int {
        receipts.reduce(0) { $0 + $1.amountCents }
    }
}

/// `sheet(item:)` needs Identifiable payloads.
private struct TextPayload: Identifiable {
    let text: String
    var id: Int { text.hashValue }
    init(_ text: String) { self.text = text }
}

private struct URLPayload: Identifiable {
    let url: URL
    var id: String { url.path }
    init(_ url: URL) { self.url = url }
}

/// The log export shares a String; an image archive has to share the file
/// itself, or the share sheet offers the path as text.
struct ShareFileSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
