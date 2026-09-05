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
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case all, topic
        var id: String { rawValue }
        var label: String { self == .all ? "All news" : "Topic label" }
    }
}

/// School configuration, kept in `UserDefaults` as JSON — like the morning-brief
/// settings, and for the same reason: it is read outside any model context.
enum SchoolConfig {
    private static let sourcesKey = "schoolSources"
    private static let profileKey = "schoolProfile"

    static var sources: [SchoolSource] {
        get {
            guard let data = UserDefaults.standard.data(forKey: sourcesKey) else { return [] }
            return (try? JSONDecoder().decode([SchoolSource].self, from: data)) ?? []
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: sourcesKey)
        }
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
