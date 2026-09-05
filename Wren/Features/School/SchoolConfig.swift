import Foundation
import WrenCore

/// A feed the app pulls from. Free text and user-entered — nothing about the
/// school is compiled in, so the real feed URL (which carries a personal token)
/// lives only on the device, never in the repo.
struct SchoolSource: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var url: String = ""
    var kind: Kind = .all

    /// `.all` is the corpus — every notice is stored from it. `.topic` feeds are
    /// a labelling pass: their items only union a label onto notices already
    /// collected, so a quiet or renamed topic costs a label, never a notice.
    /// `.calendar` is the personal iCal feed — his timetable, not news.
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case all, topic, calendar
        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return "All news"
            case .topic: return "Topic label"
            case .calendar: return "Calendar"
            }
        }
    }

    /// A calendar URL is a bearer token for the child's timetable, so it is kept
    /// in the keychain and never written to `UserDefaults`.
    var isSecret: Bool { kind == .calendar }
}

/// School configuration, kept in `UserDefaults` as JSON — like the morning-brief
/// settings, and for the same reason: it is read outside any model context.
enum SchoolConfig {
    private static let sourcesKey = "schoolSources"
    private static let profileKey = "schoolProfile"
    private static let maxAgeDaysKey = "schoolMaxAgeDays"

    /// Notices older than this are hidden — school news is termly, so a stale
    /// January post is just clutter. Pinned notices ignore it, since the school
    /// keeping one at the top is its "still current" signal. Default six weeks.
    static var maxAgeDays: Int {
        get { UserDefaults.standard.object(forKey: maxAgeDaysKey) as? Int ?? 42 }
        set { UserDefaults.standard.set(newValue, forKey: maxAgeDaysKey) }
    }

    /// The configured sources, with any secret URL resolved from the keychain on
    /// the way out and stripped back out of the plist on the way in. Callers see
    /// an ordinary `SchoolSource` with a usable `url` and never have to know
    /// which storage it came from.
    static var sources: [SchoolSource] {
        get {
            guard let data = UserDefaults.standard.data(forKey: sourcesKey) else { return [] }
            var list = (try? JSONDecoder().decode([SchoolSource].self, from: data)) ?? []
            for index in list.indices where list[index].isSecret {
                list[index].url = SchoolKeychain.get(list[index].id.uuidString) ?? ""
            }
            return list
        }
        set {
            var sanitised = newValue
            for index in sanitised.indices where sanitised[index].isSecret {
                SchoolKeychain.set(sanitised[index].url, for: sanitised[index].id.uuidString)
                // The plist keeps the source, never its token.
                sanitised[index].url = ""
            }
            UserDefaults.standard.set(try? JSONEncoder().encode(sanitised), forKey: sourcesKey)
        }
    }

    /// True once a calendar feed is set up, so the week-ahead entry only appears
    /// when there is something behind it.
    static var hasCalendar: Bool {
        sources.contains { $0.kind == .calendar && !$0.url.isEmpty }
    }

    static var profile: SchoolProfile {
        get {
            guard let data = UserDefaults.standard.data(forKey: profileKey) else { return SchoolProfile() }
            return (try? JSONDecoder().decode(SchoolProfile.self, from: data)) ?? SchoolProfile()
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: profileKey)
        }
    }

    static var isConfigured: Bool { !sources.isEmpty }
}
