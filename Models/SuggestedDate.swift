import Foundation
import SwiftData
import WrenCore

/// A date Wren pulled out of a notice, proposed to the parent as a reminder.
/// Extraction proposes; accepting it is what creates a real one-off task. A
/// dismissed suggestion is remembered so the same date is never re-proposed.
@Model
final class SuggestedDate {
    var id: UUID = UUID()
    var noticeGUID: String = ""
    var proposedTitle: String = ""
    var date: Date = Date.distantPast
    /// The body block the date came from — shown so it can be trusted or not.
    var evidence: String = ""
    /// `SchoolDeadline.Confidence` raw value: "high" or "medium".
    var confidence: String = "medium"
    /// "pending", "accepted" or "dismissed".
    var state: String = "pending"
    var createdAt: Date = Date()
    /// The one-off task made when this was accepted, if any.
    var linkedTaskID: UUID?

    init(
        id: UUID = UUID(),
        noticeGUID: String = "",
        proposedTitle: String = "",
        date: Date = .distantPast,
        evidence: String = "",
        confidence: String = "medium",
        state: String = "pending",
        createdAt: Date = Date(),
        linkedTaskID: UUID? = nil
    ) {
        self.id = id
        self.noticeGUID = noticeGUID
        self.proposedTitle = proposedTitle
        self.date = date
        self.evidence = evidence
        self.confidence = confidence
        self.state = state
        self.createdAt = createdAt
        self.linkedTaskID = linkedTaskID
    }
}

extension SuggestedDate {
    enum State: String { case pending, accepted, dismissed }

    var stateValue: State { State(rawValue: state) ?? .pending }

    var isDateInferred: Bool { confidence == SchoolDeadline.Confidence.medium.rawValue }
}
