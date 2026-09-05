import SwiftUI
import SwiftData
import WrenCore

/// One notice in full. The feed carries the whole body, so nothing is fetched
/// and nothing links out to the login wall — the text is all here.
@MainActor
struct SchoolNoticeView: View {
    let notice: SchoolNotice

    @Environment(\.modelContext) private var context
    @Environment(\.wrenTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text(notice.title.isEmpty ? "Untitled notice" : notice.title)
                        .font(WrenFont.title2)
                        .foregroundStyle(Color.wren.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(WrenFont.detail)
                        .foregroundStyle(Color.wren.textSecondary)

                    if !notice.labels.isEmpty {
                        labelRow
                    }
                }

                Divider().overlay(Color.wren.divider)

                articleBody
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.m)
            .padding(.bottom, Space.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.wren.background)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            SchoolStore.markRead(notice, context: context)
        }
    }

    /// The article, as paragraphs and bullets. Falls back to the flattened text
    /// for a notice stored before bodies were kept as HTML (until it re-fetches).
    @ViewBuilder
    private var articleBody: some View {
        let blocks = notice.bodyHTML.isEmpty
            ? (notice.bodyText.isEmpty ? [] : [SchoolBodyBlock.paragraph(notice.bodyText)])
            : SchoolBody.blocks(fromHTML: notice.bodyHTML)

        if blocks.isEmpty {
            Text("No further detail in the notice.")
                .font(.body)
                .foregroundStyle(Color.wren.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: Space.m) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    if block.isBullet {
                        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                            Text("•")
                                .font(.body)
                                .foregroundStyle(Color.wren.textSecondary)
                            Text(block.text)
                                .font(.body)
                                .foregroundStyle(Color.wren.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text(block.text)
                            .font(.body)
                            .foregroundStyle(Color.wren.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(4)
                    }
                }
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if notice.published != .distantPast {
            parts.append(notice.published.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        }
        if notice.isPinned { parts.append("pinned by the school") }
        return parts.joined(separator: " · ")
    }

    private var labelRow: some View {
        HStack(spacing: 5) {
            ForEach(notice.labels, id: \.self) { label in
                Text(label)
                    .font(WrenFont.caption)
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(theme.onHighlight)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .wrenBox(radius: Radius.chip, fill: theme.highlight)
            }
        }
    }
}
