import Foundation
import UIKit

/// Receipt images on disk. JPEG at ~0.8 quality, named by UUID, under
/// `Documents/receipts/`.
///
/// Deliberately not in SwiftData: a few hundred receipt scans as blobs would
/// bloat the store and slow every unrelated query, and the filesystem is
/// already good at holding files.
enum ReceiptFileStore {
    static let jpegQuality: CGFloat = 0.8

    static var directory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("receipts", isDirectory: true)
    }

    @discardableResult
    static func ensureDirectory() -> Bool {
        guard !FileManager.default.fileExists(atPath: directory.path) else { return true }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            Logger.record(.info, "receipts", "created \(directory.lastPathComponent) directory")
            return true
        } catch {
            Logger.record(.error, "receipts", "could not create receipts directory: \(error.localizedDescription)")
            return false
        }
    }

    static func url(for filename: String) -> URL {
        directory.appendingPathComponent(filename)
    }

    /// Writes one page and returns its filename.
    static func save(_ image: UIImage) -> String? {
        guard ensureDirectory() else { return nil }
        guard let data = image.jpegData(compressionQuality: jpegQuality) else {
            Logger.record(.error, "receipts", "could not encode a scanned page as JPEG")
            return nil
        }

        let filename = "\(UUID().uuidString).jpg"
        do {
            try data.write(to: url(for: filename), options: .atomic)
            Logger.record(.info, "receipts", "saved \(filename) (\(data.count / 1024)KB)")
            return filename
        } catch {
            Logger.record(.error, "receipts", "could not write \(filename): \(error.localizedDescription)")
            return nil
        }
    }

    static func save(_ images: [UIImage]) -> [String] {
        images.compactMap(save)
    }

    static func loadImage(_ filename: String) -> UIImage? {
        UIImage(contentsOfFile: url(for: filename).path)
    }

    /// Files are deleted only after the model row is gone, so a failure here
    /// leaves an orphan rather than a receipt with missing pages.
    static func delete(_ filenames: [String]) {
        for filename in filenames {
            do {
                try FileManager.default.removeItem(at: url(for: filename))
                Logger.record(.info, "receipts", "deleted \(filename)")
            } catch {
                Logger.record(.warn, "receipts", "could not delete \(filename): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Diagnostics

    static func fileCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path).count) ?? 0
    }

    static func totalBytes() -> Int64 {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return 0 }
        return names.reduce(into: Int64(0)) { total, name in
            let attributes = try? FileManager.default.attributesOfItem(atPath: url(for: name).path)
            total += (attributes?[.size] as? Int64) ?? 0
        }
    }

    /// Filenames on disk that no receipt references any more — surfaced in
    /// Diagnostics rather than cleaned up silently, since deleting user files on
    /// a hunch is worse than leaving a few kilobytes behind.
    static func orphanedFiles(referenced: Set<String>) -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names.filter { !referenced.contains($0) }.sorted()
    }

    // MARK: - Export

    /// Zips the given pages for sharing.
    ///
    /// Uses NSFileCoordinator's `.forUploading` read, which is the only way to
    /// produce a zip without adding a dependency — the archive it hands back is
    /// valid only inside the accessor block, so it gets copied out immediately.
    static func zip(filenames: [String], archiveName: String) -> URL? {
        guard !filenames.isEmpty else { return nil }

        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent(archiveName, isDirectory: true)
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(archiveName).zip")

        do {
            try? FileManager.default.removeItem(at: staging)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

            for filename in filenames {
                let source = url(for: filename)
                guard FileManager.default.fileExists(atPath: source.path) else {
                    Logger.record(.warn, "receipts", "export skipped missing file \(filename)")
                    continue
                }
                try FileManager.default.copyItem(at: source, to: staging.appendingPathComponent(filename))
            }

            var coordinatorError: NSError?
            var copied: URL?
            NSFileCoordinator().coordinate(
                readingItemAt: staging,
                options: [.forUploading],
                error: &coordinatorError
            ) { zipped in
                do {
                    try FileManager.default.copyItem(at: zipped, to: destination)
                    copied = destination
                } catch {
                    Logger.record(.error, "receipts", "could not copy the archive out: \(error.localizedDescription)")
                }
            }

            try? FileManager.default.removeItem(at: staging)

            if let coordinatorError {
                Logger.record(.error, "receipts", "zip failed: \(coordinatorError.localizedDescription)")
                return nil
            }

            if let copied {
                let attributes = try? FileManager.default.attributesOfItem(atPath: copied.path)
                let size = (attributes?[.size] as? Int64) ?? 0
                Logger.record(.info, "receipts", "exported \(filenames.count) page(s), \(size / 1024)KB")
            }
            return copied
        } catch {
            Logger.record(.error, "receipts", "export failed: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: staging)
            return nil
        }
    }
}
