import SwiftUI
import WrenCore

/// Configures the School feature: the feeds to pull, and who the news is ranked
/// for. Everything here is entered on the device and stored locally — the feed
/// URL carries a personal token, so it never belongs in the app itself.
///
/// A plain `Form` for now; it will get the house style once the pipeline is
/// proven on device.
@MainActor
struct SchoolSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var sources: [SchoolSource] = SchoolConfig.sources
    @State private var yearLevel: Int = SchoolConfig.profile.yearLevel
    @State private var house: String = SchoolConfig.profile.house
    @State private var activitiesText: String = SchoolConfig.profile.activities.joined(separator: ", ")
    @State private var teamsText: String = SchoolConfig.profile.teams.joined(separator: ", ")

    @State private var newName = ""
    @State private var newURL = ""
    @State private var newKind: SchoolSource.Kind = .all
    @State private var maxAgeWeeks: Int = max(1, SchoolConfig.maxAgeDays / 7)

    var body: some View {
        Form {
            profileSection
            showSection
            sourcesSection
            addSourceSection
        }
        .navigationTitle("School settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }.fontWeight(.semibold)
            }
        }
    }

    // MARK: - Profile

    private var profileSection: some View {
        Section("Your son") {
            Stepper(value: $yearLevel, in: -1...12) {
                HStack {
                    Text("Year level")
                    Spacer()
                    Text(yearLabel).foregroundStyle(.secondary)
                }
            }
            TextField("House", text: $house)
            VStack(alignment: .leading, spacing: 4) {
                TextField("Activities", text: $activitiesText, axis: .vertical)
                Text("Comma-separated — e.g. Football, Pipe Band, Chess")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                TextField("Teams", text: $teamsText, axis: .vertical)
                Text("As notices spell them — e.g. 5B, QDU 10.1")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var yearLabel: String {
        switch yearLevel {
        case -1: return "Not set"
        case 0: return "Prep"
        default: return "Year \(yearLevel)"
        }
    }

    // MARK: - Recency

    private var showSection: some View {
        Section("Show") {
            Stepper(value: $maxAgeWeeks, in: 1...26) {
                HStack {
                    Text("Recent window")
                    Spacer()
                    Text("\(maxAgeWeeks) week\(maxAgeWeeks == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                }
            }
            Text("Older notices are hidden. Anything the school has pinned always shows.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Sources

    private var sourcesSection: some View {
        Section("Feeds") {
            if sources.isEmpty {
                Text("No feeds yet. Add your school's news feed below.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sources) { source in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(source.name.isEmpty ? "Untitled" : source.name)
                                .fontWeight(.medium)
                            Spacer()
                            Text(source.kind.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(source.url)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .onDelete { sources.remove(atOffsets: $0) }
            }
        }
    }

    private var addSourceSection: some View {
        Section("Add a feed") {
            TextField("Name — e.g. All news, Year 4 Community", text: $newName)
            TextField("Feed URL", text: $newURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            Picker("Kind", selection: $newKind) {
                ForEach(SchoolSource.Kind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            Button("Add feed") { addSource() }
                .disabled(newURL.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Actions

    private func addSource() {
        let url = newURL.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { return }
        let name = newName.trimmingCharacters(in: .whitespaces)
        sources.append(SchoolSource(name: name.isEmpty ? "Feed" : name, url: url, kind: newKind))
        newName = ""; newURL = ""; newKind = .all
    }

    private func save() {
        SchoolConfig.sources = sources
        SchoolConfig.maxAgeDays = maxAgeWeeks * 7
        SchoolConfig.profile = SchoolProfile(
            yearLevel: yearLevel,
            house: house.trimmingCharacters(in: .whitespaces),
            activities: parse(activitiesText),
            teams: parse(teamsText)
        )
        dismiss()
    }

    private func parse(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
