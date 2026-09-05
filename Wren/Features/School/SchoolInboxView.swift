import SwiftUI
import SwiftData
import WrenCore

/// The suggested-dates inbox. Each row shows the date Wren found and the exact
/// text it came from, so it can be trusted before it becomes a reminder.
/// Accepting creates a one-off task; dismissing is remembered so the same date
/// is never proposed again.
///
/// This screen was rewritten twice chasing a freeze that was never in it: the
/// trigger was a *predicated* `@Query` in `SchoolView`, the view doing the
/// pushing. Hence the plain sort here — see the note on `SchoolView.suggestions`.
@MainActor
struct SchoolInboxView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \SuggestedDate.date) private var suggestions: [SuggestedDate]

    private var pending: [SuggestedDate] {
        suggestions.filter { $0.stateValue == .pending }
    }

    var body: some View {
        let pending = self.pending
        return Group {
            if pending.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        ForEach(Array(pending.enumerated()), id: \.element.id) { index, suggestion in
                            row(suggestion)
                                .wrenRow(first: index == 0, last: index == pending.count - 1)
                        }
                    } footer: {
                        WrenListFooter(text: "Notices with no date stay on the School screen and never become a reminder on their own.")
                    }
                }
                .wrenListStyle()
            }
        }
        .background(Color.wren.background)
        .navigationTitle("Suggested dates")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ suggestion: SuggestedDate) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                Text(suggestion.proposedTitle.isEmpty ? "School reminder" : suggestion.proposedTitle)
                    .font(WrenFont.heading)
                    .foregroundStyle(Color.wren.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.s)
                Text(dateLabel(suggestion.date))
                    .font(WrenFont.value)
                    .monospacedDigit()
                    .foregroundStyle(Color.wren.textPrimary)
            }

            if !suggestion.evidence.isEmpty {
                Text(quoted(suggestion.evidence))
                    .font(.subheadline)
                    .foregroundStyle(Color.wren.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if suggestion.isDateInferred {
                Text("The year wasn't written out — Wren guessed it. Check before you add.")
                    .font(.caption)
                    .foregroundStyle(Color.wren.textSecondary)
            }

            HStack(spacing: Space.s) {
                Button("Add reminder") {
                    SchoolSuggestions.accept(suggestion, context: context)
                }
                .buttonStyle(WrenCompactButtonStyle())

                Button("Not this") {
                    SchoolSuggestions.dismiss(suggestion, context: context)
                }
                .buttonStyle(WrenCompactButtonStyle(fill: .wren.surface, foreground: .wren.textPrimary))
            }
            .padding(.top, Space.xs)
        }
        .padding(.vertical, Space.xs)
    }

    private var emptyState: some View {
        VStack(spacing: Space.m) {
            WrenMark(size: 64)
                .padding(.bottom, Space.xs)
            Text("Nothing to review")
                .font(WrenFont.title3)
                .foregroundStyle(Color.wren.textPrimary)
            Text("When a notice carries a deadline or an event date, it turns up here to add as a reminder.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.wren.textSecondary)
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func dateLabel(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    private func quoted(_ text: String) -> String {
        let trimmed = text.count > 220 ? String(text.prefix(220)) + "\u{2026}" : text
        return "\u{201C}\(trimmed)\u{201D}"
    }
}
