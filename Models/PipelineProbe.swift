import Foundation
import SwiftData

/// Phase 0's throwaway model. It exists solely to prove the SwiftData container
/// opens, writes and reads on a free-tier signed build. Deleted in Phase 1 when
/// BinCollection arrives — no migration needed, the data is meaningless.
@Model
final class PipelineProbe {
    var createdAt: Date = Date()
    var note: String = ""

    init(createdAt: Date = Date(), note: String = "") {
        self.createdAt = createdAt
        self.note = note
    }
}
