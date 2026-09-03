import Foundation
import UIKit
import Vision

/// On-device text recognition. Nothing leaves the phone.
enum ReceiptOCR {

    /// Reads every page and returns the text in reading order, pages separated
    /// by blank lines.
    static func recognizeText(in images: [UIImage]) async -> String {
        var pages: [String] = []
        for (index, image) in images.enumerated() {
            let text = await recognizeText(in: image)
            Logger.shared.info("receipts", "OCR page \(index + 1): \(text.count) chars")
            if !text.isEmpty { pages.append(text) }
        }
        return pages.joined(separator: "\n\n")
    }

    static func recognizeText(in image: UIImage) async -> String {
        guard let cgImage = image.cgImage else {
            Logger.shared.warn("receipts", "OCR skipped a page with no CGImage")
            return ""
        }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    Logger.shared.error("receipts", "OCR failed: \(error.localizedDescription)")
                    continuation.resume(returning: "")
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                continuation.resume(returning: linesInReadingOrder(observations))
            }

            request.recognitionLevel = .accurate
            // Language correction "fixes" the codes, abbreviations and amounts
            // that make up most of a receipt, so it does more harm than good here.
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-AU", "en-US"]

            do {
                try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            } catch {
                Logger.shared.error("receipts", "OCR handler failed: \(error.localizedDescription)")
                continuation.resume(returning: "")
            }
        }
    }

    /// Vision returns observations in no particular order. The parser's
    /// line-based rules — "the amount on the TOTAL line" — only work if lines
    /// arrive top to bottom, so they get sorted by vertical position.
    ///
    /// Observations on roughly the same line are then ordered left to right and
    /// joined, which is what keeps a label and its amount on one line.
    private static func linesInReadingOrder(_ observations: [VNRecognizedTextObservation]) -> String {
        // Vision's origin is bottom-left, so a higher midY is further up the page.
        let sorted = observations.sorted { $0.boundingBox.midY > $1.boundingBox.midY }

        var lines: [[VNRecognizedTextObservation]] = []
        // Tolerance as a fraction of image height: anything within this of the
        // current line's baseline is treated as part of it.
        let tolerance = 0.012

        for observation in sorted {
            if let last = lines.last, let reference = last.first,
               abs(reference.boundingBox.midY - observation.boundingBox.midY) < tolerance {
                lines[lines.count - 1].append(observation)
            } else {
                lines.append([observation])
            }
        }

        return lines
            .map { line in
                line
                    .sorted { $0.boundingBox.minX < $1.boundingBox.minX }
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "  ")
            }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: "\n")
    }
}
