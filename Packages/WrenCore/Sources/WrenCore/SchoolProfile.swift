import Foundation

/// Who the news is being ranked for. Deliberately all free-form: no `enum` of
/// houses or activities, because the profile moves every year and anything
/// baked into a type is a CI round trip to change (see the build plan). Stored
/// as JSON in `UserDefaults`, like the morning-brief settings — not SwiftData,
/// since it is a single row read outside any model context.
public struct SchoolProfile: Codable, Hashable, Sendable {
    /// `0` = Prep, then Year 1…12.
    public var yearLevel: Int
    public var house: String
    /// Free text: "Football", "Pipe Band", "Colla Voce" — whatever the family
    /// actually does. Matched case-insensitively against notice text.
    public var activities: [String]
    /// Team/grade tokens as notices spell them: "5B", "QDU 10.1". Only useful
    /// once known, and only discoverable from a notice or from the parent.
    public var teams: [String]

    public init(yearLevel: Int = -1, house: String = "", activities: [String] = [], teams: [String] = []) {
        self.yearLevel = yearLevel
        self.house = house
        self.activities = activities
        self.teams = teams
    }

    public enum Section: String, Sendable {
        case junior, secondary, unknown
    }

    /// Prep–6 is Junior School, 7–12 Secondary. Derived, never stored.
    public var section: Section {
        switch yearLevel {
        case 0...6: return .junior
        case 7...12: return .secondary
        default: return .unknown
        }
    }

    /// `true` once a year level has been set. `-1` is the unset sentinel, so a
    /// fresh install ranks nothing as "for him" until the parent fills it in.
    public var isConfigured: Bool { yearLevel >= 0 }

    /// "Year 4", "Prep".
    public var yearLabel: String {
        yearLevel == 0 ? "Prep" : "Year \(yearLevel)"
    }
}
