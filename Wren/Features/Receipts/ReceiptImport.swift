import Foundation
import PDFKit
import UIKit

/// Turns a file the user picked — a PDF or an image — into the same pages the
/// document scanner produces, so everything downstream stays identical.
enum ReceiptImport {

    /// A PDF page rendered much larger than this gains nothing for OCR and
    /// costs memory; much smaller and small print stops resolving.
    private static let renderScale: CGFloat = 2.0
    /// Below this many characters a PDF's text layer is assumed to be absent or
    /// junk — a scanned invoice often carries a few stray marks — and OCR runs
    /// instead.
    private static let usableTextThreshold = 20

    struct Imported {
        let images: [UIImage]
        /// Text lifted straight from a PDF's text layer, when it had one.
        /// Perfectly accurate, unlike OCR, so it is used in preference.
        let embeddedText: String?
    }

    /// Reads a security-scoped URL from the file picker.
    static func load(from url: URL) -> Imported? {
        // Files chosen through the picker come security-scoped; without this the
        // read fails with a permission error that looks like a missing file.
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        if url.pathExtension.lowercased() == "pdf" {
            return loadPDF(at: url)
        }
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else {
            Logger.record(.error, "receipts", "could not read \(url.lastPathComponent) as an image")
            return nil
        }
        Logger.record(.info, "receipts", "imported image \(url.lastPathComponent)")
        return Imported(images: [image], embeddedText: nil)
    }

    static func load(imageData: Data) -> Imported? {
        guard let image = UIImage(data: imageData) else {
            Logger.record(.error, "receipts", "could not decode the chosen photo")
            return nil
        }
        Logger.record(.info, "receipts", "imported a photo from the library")
        return Imported(images: [image], embeddedText: nil)
    }

    // MARK: - PDF

    private static func loadPDF(at url: URL) -> Imported? {
        guard let document = PDFDocument(url: url) else {
            Logger.record(.error, "receipts", "could not open \(url.lastPathComponent) as a PDF")
            return nil
        }

        var images: [UIImage] = []
        var text = ""

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            if let rendered = render(page) { images.append(rendered) }
            if let pageText = page.string { text += pageText + "\n" }
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let usable = trimmed.count >= usableTextThreshold

        Logger.record(
            .info,
            "receipts",
            "imported PDF \(url.lastPathComponent): \(images.count) page(s), "
                + (usable ? "\(trimmed.count) chars of embedded text" : "no usable text layer, will OCR")
        )

        guard !images.isEmpty else { return nil }
        return Imported(images: images, embeddedText: usable ? trimmed : nil)
    }

    private static func render(_ page: PDFPage) -> UIImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let size = CGSize(width: bounds.width * renderScale, height: bounds.height * renderScale)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            // PDF pages are drawn bottom-up, so the context is flipped before
            // drawing or every page comes out upside down.
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: renderScale, y: -renderScale)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
    }
}
