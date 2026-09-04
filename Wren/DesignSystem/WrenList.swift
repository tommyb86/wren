import SwiftUI

// The section lists stay on `List` so swipe actions, delete and the platform's
// scrolling stay native. The look comes from each row painting its own share
// of the section box: the fill, the side borders, and the top or bottom edge
// with its corners when the row is first or last in its section.

/// One row's share of the bordered box. It paints only inside its own bounds
/// (the shape is bled past the row on the edges it doesn't own and clipped),
/// so neighbouring rows never fight over who draws the line between them.
struct WrenRowBackground: View {
    var first: Bool
    var last: Bool

    var body: some View {
        GeometryReader { geometry in
            let bleed: CGFloat = 20
            let shape = UnevenRoundedRectangle(
                topLeadingRadius: first ? Radius.card : 0,
                bottomLeadingRadius: last ? Radius.card : 0,
                bottomTrailingRadius: last ? Radius.card : 0,
                topTrailingRadius: first ? Radius.card : 0,
                style: .continuous
            )
            ZStack {
                shape.fill(Color.wren.surface)
                shape.strokeBorder(Color.wren.textPrimary, lineWidth: Stroke.border)
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height + (first ? 0 : bleed) + (last ? 0 : bleed)
            )
            .offset(y: first ? 0 : -bleed)
        }
        .clipped()
        .padding(.horizontal, Space.l)
    }
}

extension View {
    /// One row of a bordered section. `first` and `last` decide which edges
    /// it draws; a row that is both is a box on its own.
    func wrenRow(first: Bool = false, last: Bool = false) -> some View {
        self
            .listRowInsets(EdgeInsets(top: Space.s, leading: Space.l + Space.m, bottom: Space.s, trailing: Space.l + Space.m))
            .listRowBackground(WrenRowBackground(first: first, last: last))
            .listRowSeparatorTint(Color.wren.divider)
            .listRowSeparator(.hidden, edges: .top)
            .listRowSeparator(last ? .hidden : .visible, edges: .bottom)
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            .alignmentGuide(.listRowSeparatorTrailing) { $0[.trailing] }
    }

    /// The container for `wrenRow` rows: plain, on paper, no section rules.
    func wrenListStyle() -> some View {
        self
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .listSectionSeparator(.hidden)
            .background(Color.wren.background)
    }
}

/// Section header for a `wrenListStyle` list: the uppercase label, with an
/// optional figure on the right.
struct WrenListHeader: View {
    let text: String
    var color: Color = .wren.textPrimary
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            WrenSectionLabel(text: text, color: color)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(WrenFont.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.wren.textSecondary)
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.xl)
        .padding(.bottom, Space.s + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets())
        // The row's own background, not just the label's: a plain list still
        // paints its rows, which showed as white bands around the text.
        .listRowBackground(Color.wren.background)
        .listRowSeparator(.hidden)
        .textCase(nil)
    }
}

/// Explanatory prose under a section box. Sits on the paper, outside the
/// border, because it is commentary rather than content.
struct WrenListFooter: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Color.wren.textSecondary)
            .padding(.horizontal, Space.l)
            .padding(.top, Space.s)
            .padding(.bottom, Space.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.wren.background)
            .listRowSeparator(.hidden)
            .textCase(nil)
    }
}

/// A label and its figure: the standard row inside a bordered stat box.
struct WrenStatRow: View {
    let label: String
    let value: String
    var valueColor: Color = .wren.textPrimary
    /// The line the section is really about, e.g. what's still outstanding.
    var emphasised: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            Text(label)
                .font(emphasised ? WrenFont.value : .subheadline.weight(.medium))
                .foregroundStyle(emphasised ? Color.wren.textPrimary : Color.wren.textSecondary)
            Spacer(minLength: Space.s)
            Text(value)
                .font(WrenFont.value)
                .monospacedDigit()
                .foregroundStyle(valueColor)
        }
        .padding(.vertical, Space.xs)
    }
}

/// The navigation-bar action as a small highlight block.
struct WrenToolbarIcon: View {
    let systemName: String

    @Environment(\.wrenTheme) private var theme

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .black))
            .foregroundStyle(theme.onHighlight)
            .frame(width: 30, height: 30)
            .wrenBox(radius: Radius.chip, fill: theme.highlight)
            .wrenHardShadow(radius: Radius.chip)
    }
}
