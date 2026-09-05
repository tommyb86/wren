import SwiftUI
import SwiftData
import WrenCore

/// The suggested-dates review queue: each row is a date Wren found and the text
/// it came from, so it can be trusted before it becomes a reminder. Accepting
/// creates a one-off task; dismissing is remembered so the same date is never
/// proposed again.
///
/// Presented as a sheet over a plain `Form`, and that is deliberate. Two earlier
/// versions of this screen hung on device: first a `ScrollView` of cards, then a
/// styled `List` built exactly like `TasksListView`. Since the second rewrite
/// changed the whole body and changed nothing about the symptom, the cause is
/// not the row content — it is something in the pushed presentation or the
/// custom row chrome (`WrenRowBackground`'s `GeometryReader`, and
/// `WrenCompactButtonStyle`'s shadow and press animation inside a list row).
///
/// So this version keeps none of it. Sheet, `Form`, stock buttons — the same
/// construction as `SchoolSettingsView`, which is presented from this very
/// screen and works. The house style comes back once this is known good on
/// device, one piece at a time.
@MainActor
struct SchoolInboxView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<SuggestedDate> { $0.state == "pending" }, sort: \SuggestedDate.date)
    private var pending: [SuggestedDate]

    var body: some View {
        Form {
            if pending.isEmpty {
                emptySection
            } else {
                ForEach(pending, id: \.id) { suggestion in
                    Section {
                        rows(for: suggestion)
                    }
                }

                Section {
                    Text("Notices with no date stay on the School screen and never become a reminder on their own.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Suggested dates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }.fontWeight(.semibold)
            }
        }
    }

    private var emptySection: some View {
        Section {
            Text("Nothing to review")
                .font(.headline)
            Text("When a notice carries a deadline or an event date, it turns up here to add as a reminder.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// One suggestion, as a handful of ordinary form rows.
    @ViewBuilder
    private func rows(for suggestion: SuggestedDate) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(suggestion.proposedTitle.isEmpty ? "School reminder" : suggestion.proposedTitle)
                .font(.headline)
            Text(dateLabel(suggestion.date))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }

        if !suggestion.evidence.isEmpty {
            Text(quoted(suggestion.evidence))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        if suggestion.isDateInferred {
            Text("The year wasn't written out — Wren guessed it. Check before you add.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Button("Add reminder") {
            SchoolSuggestions.accept(suggestion, context: context)
        }

        Button("Not this", role: .destructive) {
            SchoolSuggestions.dismiss(suggestion, context: context)
        }
    }

    private func dateLabel(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private func quoted(_ text: String) -> String {
        let trimmed = text.count > 220 ? String(text.prefix(220)) + "\u{2026}" : text
        return "\u{201C}\(trimmed)\u{201D}"
    }
}
