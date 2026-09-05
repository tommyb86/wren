import SwiftUI
import SwiftData
import WrenCore

/// The suggested-dates inbox. Each card shows the date Wren found and the exact
/// text it came from, so it can be trusted before it becomes a reminder.
/// Accepting creates a one-off task; dismissing is remembered so the same date
/// is never proposed again.
@MainActor
struct SchoolInboxView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<SuggestedDate> { $0.state == "pending" }, sort: \SuggestedDate.date)
    private var pending: [SuggestedDate]

    @Environment(\.wrenTheme) private var theme

    var body: some View {
        Group {
            if pending.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: Space.l) {
                        ForEach(pending) { suggestion in
                            card(suggestion)
                        }
                        footer
                    }
                    .padding(Space.l)
                }
            }
        }
        .background(Color.wren.background)
        .navigationTitle("Suggested dates")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func card(_ suggestion: SuggestedDate) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .top, spacing: Space.m) {
                Text(suggestion.proposedTitle.isEmpty ? "School reminder" : suggestion.proposedTitle)
                    .font(WrenFont.heading)
                    .foregroundStyle(Color.wren.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                WrenChip(text: dateLabel(suggestion.date))
            }

            if !suggestion.evidence.isEmpty {
                Text(quoted(suggestion.evidence))
                    .font(.subheadline)
                    .foregroundStyle(Color.wren.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, Space.m)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.wren.divider)
                            .frame(width: Stroke.border)
                    }
            }

            if suggestion.isDateInferred {
                Text("The year wasn't written out — Wren guessed it. Check before you add.")
                    .font(.caption)
                    .foregroundStyle(Color.wren.textSecondary)
            }

            HStack(spacing: Space.s) {
                Button {
                    SchoolSuggestions.accept(suggestion, context: context)
                } label: {
                    Text("Add reminder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WrenCompactButtonStyle())

                Button {
                    SchoolSuggestions.dismiss(suggestion, context: context)
                } label: {
                    Text("Not this")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WrenCompactButtonStyle(fill: .wren.surface, foreground: .wren.textPrimary))
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wrenBox()
    }

    private var footer: some View {
        Text("Notices with no date stay on the School screen and never become a reminder on their own.")
            .font(.caption)
            .foregroundStyle(Color.wren.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.xs)
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
        let trimmed = text.count > 220 ? String(text.prefix(220)) + "…" : text
        return "\u{201C}\(trimmed)\u{201D}"
    }
}
