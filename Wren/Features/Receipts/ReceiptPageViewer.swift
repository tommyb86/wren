import SwiftUI

/// Full-screen receipt pages: swipe between them, pinch or double-tap to zoom,
/// share one out.
///
/// Sharing a single page matters more than it looks — "send me the receipt" is
/// the most common thing anyone actually does with one.
@MainActor
struct ReceiptPageViewer: View {
    let filenames: [String]
    @State var index: Int

    @Environment(\.dismiss) private var dismiss
    @State private var sharedPage: URL?

    var body: some View {
        NavigationStack {
            Group {
                if filenames.isEmpty {
                    Text("No pages to show.")
                        .font(.subheadline)
                        .foregroundStyle(Color.wren.textSecondary)
                } else {
                    TabView(selection: $index) {
                        ForEach(Array(filenames.enumerated()), id: \.element) { offset, filename in
                            page(filename)
                                .tag(offset)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: filenames.count > 1 ? .automatic : .never))
                }
            }
            // Follows the theme rather than a hard black lightbox: in dark mode
            // this is near-black anyway, and in light mode a paper surround
            // suits a paper receipt.
            .background(Color.wren.background)
            .navigationTitle(filenames.count > 1 ? "Page \(index + 1) of \(filenames.count)" : "Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        guard filenames.indices.contains(index) else { return }
                        sharedPage = ReceiptFileStore.url(for: filenames[index])
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share this page")
                    .disabled(filenames.isEmpty)
                }
            }
            .sheet(item: Binding(
                get: { sharedPage.map(SharedPage.init) },
                set: { sharedPage = $0?.url }
            )) { shared in
                ShareFileSheet(url: shared.url)
            }
        }
    }

    @ViewBuilder
    private func page(_ filename: String) -> some View {
        if let image = ReceiptFileStore.loadImage(filename) {
            ZoomableImage(image: image)
        } else {
            // A missing file means the row outlived its image — worth saying so
            // rather than showing an empty screen.
            VStack(spacing: Space.s) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(Color.wren.alert)
                Text("This page is missing from storage.")
                    .font(.subheadline)
                    .foregroundStyle(Color.wren.textSecondary)
            }
        }
    }
}

private struct SharedPage: Identifiable {
    let url: URL
    var id: String { url.path }
    init(_ url: URL) { self.url = url }
}
