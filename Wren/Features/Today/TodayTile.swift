import SwiftUI

/// One of the four section tiles under the summary. The tile is the link to
/// its section, so the stat it shows is the thing you'd open the section to
/// find out.
struct TodayTile: View {
    let label: String
    let value: String
    let detail: String
    var swatch: Color? = nil
    var detailColor: Color = .wren.textSecondary

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text(label)
                .font(.caption.weight(.bold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(Color.wren.textSecondary)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.s) {
                    if let swatch {
                        WrenLidSwatch(color: swatch)
                    }
                    Text(value)
                        .font(.body.weight(.bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(Color.wren.textPrimary)
                }
                Text(detail)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(detailColor)
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .wrenBox()
        .contentShape(.rect)
    }
}
