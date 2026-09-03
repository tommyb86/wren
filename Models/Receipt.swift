import Foundation
import SwiftData
import WrenCore

/// A captured receipt. Images live on disk under `Documents/receipts/` and only
/// their filenames are stored here — image blobs in SwiftData bloat the store
/// and make every query slower for no benefit.
@Model
final class Receipt {
    var receiptID: UUID = UUID()
    var vendor: String = ""
    var amountCents: Int = 0
    /// The date on the receipt, not when it was captured — that is what decides
    /// which financial year it belongs to.
    var date: Date = Date()
    var category: String = ""
    var notes: String = ""
    /// Kept verbatim so full-text search stays possible later without a re-scan.
    var rawOCRText: String = ""
    /// Filenames in the receipts directory, in page order.
    var imageFilenames: [String] = []
    var createdAt: Date = Date()

    init(
        receiptID: UUID = UUID(),
        vendor: String = "",
        amountCents: Int = 0,
        date: Date = Date(),
        category: String = "",
        notes: String = "",
        rawOCRText: String = "",
        imageFilenames: [String] = [],
        createdAt: Date = Date()
    ) {
        self.receiptID = receiptID
        self.vendor = vendor
        self.amountCents = amountCents
        self.date = date
        self.category = category
        self.notes = notes
        self.rawOCRText = rawOCRText
        self.imageFilenames = imageFilenames
        self.createdAt = createdAt
    }
}

extension Receipt {
    /// Australian FY, derived from the receipt's own date.
    func financialYear(calendar: Calendar = .current) -> FinancialYear {
        FinancialYear.containing(date, calendar: calendar)
    }

    var displayVendor: String {
        vendor.trimmingCharacters(in: .whitespaces).isEmpty ? "Unknown vendor" : vendor
    }

    var pageCount: Int { imageFilenames.count }
}
