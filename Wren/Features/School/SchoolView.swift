import SwiftUI
import SwiftData
import WrenCore

/// One notice as ranked for display: the notice, the tags that placed it, and a
/// series count when it stands in for a collapsed run of daily posts.
private struct RankedNotice: Identifiable {
    let notice: SchoolNotice
    let tags: [SchoolTag]
    let seriesCount: Int
    var id: String { notice.guid }
}

/// The School screen. Ranks every stored notice into For-him / Whole-school /
/// Everything-else, collapses running series, and never hides anything.
@MainActor
struct SchoolView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SchoolNotice.published, order: .reverse) private var notices: [SchoolNotice]

    @State private var showingSettings = false

    private var profile: SchoolProfile { SchoolConfig.profile }

    var body: some View {
        Group {
            if !SchoolConfig.isConfigured {
                emptyState(
                    title: "No feed yet",
                    message: "Add your school's news feed and its notices turn up here, ranked for your son.",
                    cta: "Add a feed"
                )
            } else if notices.isEmpty {
                emptyState(
                    title: "Nothing yet",
                    message: "Pull down to refresh. If it stays empty, check the feed URL in settings.",
                    cta: "Open settings"
                )
            } else {
                list
            }
        }
        .background(Color.wren.background)
        .navigationTitle("School")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingSettings = true } label: {
                    WrenToolbarIcon(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("School settings")
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack { SchoolSettingsView() }
        }
        .task { await SchoolStore.refresh(context: context) }
        .refreshable { await SchoolStore.refresh(context: context) }
    }

    // MARK: - List

    private var list: some View {
        let ranked = rank()
        return List {
            summary(ranked)

            if !ranked.forMe.isEmpty {
                section(profile.isConfigured ? "For \(profile.yearLabel)" : "Matched", rows: ranked.forMe)
            }
            if !ranked.whole.isEmpty {
                section("Whole school", rows: ranked.whole)
            }
            if !ranked.rest.isEmpty {
                section("Everything else", rows: ranked.rest, quiet: true)
            }
        }
        .wrenListStyle()
    }

    private func summary(_ ranked: (forMe: [RankedNotice], whole: [RankedNotice], rest: [RankedNotice])) -> some View {
        Text(summaryText(ranked))
            .font(WrenFont.detail)
            .foregroundStyle(Color.wren.textSecondary)
            .padding(.horizontal, Space.l)
            .padding(.top, Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.wren.background)
            .listRowSeparator(.hidden)
    }

    private func summaryText(_ ranked: (forMe: [RankedNotice], whole: [RankedNotice], rest: [RankedNotice])) -> String {
        let forMe = ranked.forMe.count
        let shown = ranked.forMe.count + ranked.whole.count + ranked.rest.reduce(0) { $0 + $1.seriesCount }
        if forMe > 0 {
            return "\(forMe) for \(profile.isConfigured ? profile.yearLabel.lowercased() : "you") · \(shown) recent notices"
        }
        return "\(shown) recent notices — nothing matched your son yet"
    }

    private func section(_ title: String, rows: [RankedNotice], quiet: Bool = false) -> some View {
        Section {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, ranked in
                NavigationLink {
                    SchoolNoticeView(notice: ranked.notice)
                } label: {
                    SchoolNoticeRow(ranked: ranked)
                }
                .wrenRow(first: index == 0, last: index == rows.count - 1)
            }
        } header: {
            WrenListHeader(
                text: title,
                color: quiet ? .wren.textSecondary : .wren.textPrimary,
                trailing: "\(rows.count)"
            )
        }
    }

    // MARK: - Ranking

    private func rank() -> (forMe: [RankedNotice], whole: [RankedNotice], rest: [RankedNotice]) {
        let profile = self.profile
        var forMe: [SchoolNotice] = []
        var whole: [SchoolNotice] = []
        var rest: [SchoolNotice] = []
        var tagsByGuid: [String: [SchoolTag]] = [:]

        // Hide stale notices, but always keep the ones the school has pinned.
        let cutoff = Calendar.current.date(byAdding: .day, value: -SchoolConfig.maxAgeDays, to: Date()) ?? .distantPast
        let recent = notices.filter { $0.isPinned || $0.published >= cutoff }

        for notice in recent {
            let match = SchoolRelevance.match(notice.feedItem, profile: profile)
            tagsByGuid[notice.guid] = match.tags
            switch match.bucket {
            case .forMe: forMe.append(notice)
            case .wholeSchool: whole.append(notice)
            case .everythingElse: rest.append(notice)
            }
        }

        func ordered(_ list: [SchoolNotice]) -> [RankedNotice] {
            list.sorted { a, b in
                if a.isPinned != b.isPinned { return a.isPinned && !b.isPinned }
                return a.published > b.published
            }
            .map { RankedNotice(notice: $0, tags: tagsByGuid[$0.guid] ?? [], seriesCount: 1) }
        }

        // Everything else: collapse running series to one representative row.
        let restByGuid = Dictionary(rest.map { ($0.guid, $0) }, uniquingKeysWith: { a, _ in a })
        var restRows: [RankedNotice] = []
        for group in SchoolSeries.group(rest.map(\.feedItem)) {
            guard let latest = group.latest, let notice = restByGuid[latest.guid] else { continue }
            restRows.append(RankedNotice(notice: notice, tags: [], seriesCount: group.isSeries ? group.count : 1))
        }

        return (ordered(forMe), ordered(whole), restRows)
    }

    // MARK: - Empty state

    private func emptyState(title: String, message: String, cta: String) -> some View {
        VStack(spacing: Space.m) {
            WrenMark(size: 64)
                .padding(.bottom, Space.xs)
            Text(title)
                .font(WrenFont.title3)
                .foregroundStyle(Color.wren.textPrimary)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.wren.textSecondary)
            Button(cta) { showingSettings = true }
                .buttonStyle(WrenPrimaryButtonStyle())
                .padding(.top, Space.s)
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A notice as a list row: title, a detail line, its match tags, and an unread
/// mark. Filled tags are the school's own labels; outlined tags are inferred.
private struct SchoolNoticeRow: View {
    let ranked: RankedNotice

    @Environment(\.wrenTheme) private var theme

    private var notice: SchoolNotice { ranked.notice }

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 5) {
                Text(notice.title.isEmpty ? "Untitled notice" : notice.title)
                    .font(WrenFont.heading)
                    .foregroundStyle(Color.wren.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detail)
                    .font(WrenFont.detail)
                    .foregroundStyle(Color.wren.textSecondary)

                if !ranked.tags.isEmpty {
                    tagRow
                }
            }

            Spacer(minLength: 0)

            if !notice.isRead {
                Circle()
                    .fill(theme.highlight)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(Color.wren.textPrimary, lineWidth: 1))
                    .padding(.top, 6)
            }
        }
        .padding(.vertical, Space.xs)
    }

    private var detail: String {
        var parts: [String] = []
        if notice.published != .distantPast {
            parts.append(notice.published.formatted(.dateTime.day().month(.abbreviated)))
        }
        if notice.isPinned { parts.append("pinned") }
        if ranked.seriesCount > 1 { parts.append("\(ranked.seriesCount) posts") }
        return parts.joined(separator: " · ")
    }

    private var tagRow: some View {
        HStack(spacing: 5) {
            ForEach(Array(ranked.tags.prefix(3).enumerated()), id: \.offset) { _, tag in
                Text(tag.label)
                    .font(WrenFont.caption)
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(tag.isSchoolLabel ? theme.onHighlight : Color.wren.textPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tag.isSchoolLabel ? theme.highlight : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                            .strokeBorder(Color.wren.textPrimary, lineWidth: 1.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
            }
        }
    }
}
