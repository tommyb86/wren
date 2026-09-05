import Foundation

/// Where a notice sits relative to one boy: something for him, something for the
/// whole school, or everything else. Ranking, never filtering — every notice
/// lands in exactly one bucket, and none is hidden.
public enum SchoolBucket: String, Sendable, Hashable {
    case forMe
    case wholeSchool
    case everythingElse
}

/// A reason a notice was placed where it was. `isSchoolLabel` distinguishes a
/// classification the school itself made (a topic feed) from one Wren inferred
/// from the text — the UI fills the former and outlines the latter, so a glance
/// separates fact from guess.
public struct SchoolTag: Hashable, Sendable {
    public let label: String
    public let isSchoolLabel: Bool

    public init(label: String, isSchoolLabel: Bool) {
        self.label = label
        self.isSchoolLabel = isSchoolLabel
    }
}

public struct SchoolMatch: Hashable, Sendable {
    public let bucket: SchoolBucket
    public let tags: [SchoolTag]

    public init(bucket: SchoolBucket, tags: [SchoolTag]) {
        self.bucket = bucket
        self.tags = tags
    }
}

public enum SchoolRelevance {
    /// Topics that matter regardless of the boy — the "always show" set.
    private static let alwaysShow: [(tag: String, terms: [String])] = [
        ("Uniform", ["uniform", "blazer", "boater", "haircut", "school shoes", "kit"]),
        ("Transport", ["bus service", "parking", "car park", "drop-off", "kiss and", "e-bike", "e-scooter"]),
        ("Term dates", ["term date", "pupil free", "student free", "public holiday", "last day of term", "holidays"])
    ]

    private static let negatives = [
        "old boy", "old collegian", "class of 19", "class of 20",
        "reunion", "boarder", "vintage collegian", "alumni", "50 year", "60 year"
    ]

    /// Classifies one item against a profile. Provenance first (a school label),
    /// then always-show topics, then text (activities, year range, teams), and
    /// finally negatives demote anything that reached none of those.
    public static func match(_ item: SchoolFeedItem, profile: SchoolProfile) -> SchoolMatch {
        let haystack = (item.title + " \n " + item.bodyText).lowercased()

        // 1. Provenance — the school's own classification wins outright.
        if !item.labels.isEmpty {
            let tags = item.labels.map { SchoolTag(label: $0, isSchoolLabel: true) }
            return SchoolMatch(bucket: .forMe, tags: tags)
        }

        var tags: [SchoolTag] = []

        // 2. Text signals that make it his.
        if profile.isConfigured {
            for activity in profile.activities where !activity.isEmpty {
                if haystack.contains(activity.lowercased()) {
                    tags.append(SchoolTag(label: activity, isSchoolLabel: false))
                }
            }
            for team in profile.teams where !team.isEmpty {
                if containsToken(haystack, token: team.lowercased()) {
                    tags.append(SchoolTag(label: team, isSchoolLabel: false))
                }
            }
            if yearMatches(haystack, profile: profile) {
                tags.append(SchoolTag(label: profile.yearLabel, isSchoolLabel: false))
            }
        }

        if !tags.isEmpty {
            return SchoolMatch(bucket: .forMe, tags: tags)
        }

        // 3. Always-show topics → whole school.
        var topicTags: [SchoolTag] = []
        for topic in alwaysShow where topic.terms.contains(where: { haystack.contains($0) }) {
            topicTags.append(SchoolTag(label: topic.tag, isSchoolLabel: false))
        }
        if !topicTags.isEmpty {
            return SchoolMatch(bucket: .wholeSchool, tags: topicTags)
        }

        // 4. Everything else — including anything a negative pushed down.
        return SchoolMatch(bucket: .everythingElse, tags: [])
    }

    /// `true` if this notice concerns the boy's year — by an explicit range
    /// ("Year 4 to Year 11"), a bare mention ("Year 4"), or his school section
    /// ("Junior School"). The range case is the one substring matching fails.
    static func yearMatches(_ text: String, profile: SchoolProfile) -> Bool {
        let level = profile.yearLevel

        // Section words.
        if profile.section == .junior, text.contains("junior school") { return true }
        if profile.section == .secondary,
           text.contains("senior school") || text.contains("secondary school") { return true }

        // "prep to year 6" / "prep – year 6".
        if text.range(of: "prep\\s*[\u{2013}\u{2014}-]?\\s*(to)?\\s*year\\s*6", options: .regularExpression) != nil {
            if (0...6).contains(level) { return true }
        }

        // Explicit ranges: "year 4 to year 11", "years 5-8", "year 4–11".
        if let regex = try? NSRegularExpression(
            pattern: "years?\\s*(\\d{1,2})\\s*(?:to|and|[\u{2013}\u{2014}-])\\s*(?:year\\s*)?(\\d{1,2})",
            options: [.caseInsensitive]
        ) {
            let ns = text as NSString
            for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                if let lo = Int(ns.substring(with: m.range(at: 1))),
                   let hi = Int(ns.substring(with: m.range(at: 2))),
                   lo <= hi, (lo...hi).contains(level) {
                    return true
                }
            }
        }

        // Bare "year N" mentions.
        if level >= 1, let regex = try? NSRegularExpression(
            pattern: "year\\s*(\\d{1,2})",
            options: [.caseInsensitive]
        ) {
            let ns = text as NSString
            for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                if Int(ns.substring(with: m.range(at: 1))) == level { return true }
            }
        }
        if level == 0, text.contains("prep") { return true }

        return false
    }

    /// Whole-word-ish containment, so a team token like "5b" does not match
    /// inside "5businesses". Boundaries are non-alphanumerics.
    static func containsToken(_ text: String, token: String) -> Bool {
        guard !token.isEmpty else { return false }
        let escaped = NSRegularExpression.escapedPattern(for: token)
        guard let regex = try? NSRegularExpression(
            pattern: "(?<![a-z0-9])\(escaped)(?![a-z0-9])",
            options: [.caseInsensitive]
        ) else { return text.contains(token) }
        let ns = text as NSString
        return regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) != nil
    }

    /// `true` if the notice reads as alumni/old-boy/boarder material — surfaced
    /// so the ranking can keep it out of the way even when it mentions a year.
    public static func isNegative(_ item: SchoolFeedItem) -> Bool {
        let haystack = (item.title + " " + item.bodyText).lowercased()
        return negatives.contains { haystack.contains($0) }
    }
}
