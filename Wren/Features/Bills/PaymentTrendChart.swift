import SwiftUI
import WrenCore

/// Recorded payments for a variable bill over time.
///
/// A line rather than bars: bars invite comparison between discrete things,
/// a line says "this is one thing changing", which is the question being asked.
/// Single series, so no legend — the section title names it. The expected
/// amount sits behind as a recessive reference line, so over and under read at
/// a glance without spending a second colour.
///
/// Deliberately no fitted trendline, and the title never says "trend": see
/// `PaymentTrend` for why a regression here would mislead.
@MainActor
struct PaymentTrendChart: View {
    let trend: PaymentTrend
    let expectedCents: Int
    @Binding var selection: TrendPoint?

    private let plotHeight: CGFloat = 120
    private let markerSize: CGFloat = 9

    /// Padded so the line never touches the frame edge, and always includes the
    /// expected line even when every payment sits far from it.
    private var bounds: (low: Int, high: Int) {
        let values = trend.points.map(\.amountCents) + [expectedCents]
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        guard high > low else { return (low - 100, high + 100) }
        let padding = Int(Double(high - low) * 0.15)
        return (low - padding, high + padding)
    }

    private func y(for cents: Int, in height: CGFloat) -> CGFloat {
        let (low, high) = bounds
        let span = max(high - low, 1)
        let fraction = Double(cents - low) / Double(span)
        return height - (height * fraction)
    }

    private func x(for index: Int, in width: CGFloat) -> CGFloat {
        // Ordinal spacing: each point is a billing period, not a moment in time,
        // so periods are evenly spaced regardless of how the dates fall.
        guard trend.points.count > 1 else { return width / 2 }
        return width * CGFloat(index) / CGFloat(trend.points.count - 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            plot
            caption
        }
    }

    private var plot: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack(alignment: .topLeading) {
                expectedLine(width: width, height: height)
                connectingLine(width: width, height: height)
                markers(width: width, height: height)
                hitTargets(width: width, height: height)
            }
        }
        .frame(height: plotHeight)
        .padding(.vertical, Space.s)
    }

    private func expectedLine(width: CGFloat, height: CGFloat) -> some View {
        let position = y(for: expectedCents, in: height)
        return Path { path in
            path.move(to: CGPoint(x: 0, y: position))
            path.addLine(to: CGPoint(x: width, y: position))
        }
        .stroke(Color.wren.divider, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
    }

    private func connectingLine(width: CGFloat, height: CGFloat) -> some View {
        Path { path in
            for (index, point) in trend.points.enumerated() {
                let position = CGPoint(x: x(for: index, in: width), y: y(for: point.amountCents, in: height))
                if index == 0 {
                    path.move(to: position)
                } else {
                    path.addLine(to: position)
                }
            }
        }
        .stroke(Color.wren.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    private func markers(width: CGFloat, height: CGFloat) -> some View {
        ForEach(Array(trend.points.enumerated()), id: \.element.id) { index, point in
            let isSelected = selection?.id == point.id

            Circle()
                .fill(point.isOutlier ? Color.wren.surface : Color.wren.accent)
                .overlay(
                    Circle().strokeBorder(Color.wren.accent, lineWidth: point.isOutlier ? 2 : 0)
                )
                // A 2px surface ring keeps overlapping marks legible.
                .overlay(
                    Circle().strokeBorder(Color.wren.surface, lineWidth: isSelected ? 0 : 2).blendMode(.destinationOver)
                )
                .frame(width: isSelected ? markerSize + 4 : markerSize,
                       height: isSelected ? markerSize + 4 : markerSize)
                .position(x: x(for: index, in: width), y: y(for: point.amountCents, in: height))
        }
    }

    /// Hit targets are the full column, not the 9pt dot.
    private func hitTargets(width: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(trend.points) { point in
                Rectangle()
                    .fill(.clear)
                    .contentShape(.rect)
                    .onTapGesture {
                        withAnimation(.snappy(duration: 0.2)) {
                            selection = selection?.id == point.id ? nil : point
                        }
                    }
                    .accessibilityLabel(
                        "\(point.dueDate.formatted(.dateTime.day().month().year())): "
                            + Money.format(cents: point.amountCents)
                            + (point.isOutlier ? ", unusual" : "")
                    )
            }
        }
        .frame(width: width, height: height)
    }

    /// Selective direct labels: the selected point, or the latest one. Never a
    /// number on every point.
    private var caption: some View {
        let highlighted = selection ?? trend.latest

        return VStack(alignment: .leading, spacing: 2) {
            if let highlighted {
                HStack(spacing: Space.xs) {
                    Text(Money.format(cents: highlighted.amountCents))
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.wren.textPrimary)
                    Text(highlighted.dueDate.formatted(.dateTime.day().month().year()))
                        .font(.caption)
                        .foregroundStyle(Color.wren.textSecondary)
                    if selection == nil {
                        Text("· latest")
                            .font(.caption)
                            .foregroundStyle(Color.wren.textSecondary)
                    }
                    Spacer()
                    Text("median \(Money.formatWholeDollars(cents: trend.medianCents))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Color.wren.textSecondary)
                }
            }

            if let highlighted, highlighted.isOutlier {
                // Naming the likely cause, because in a short series an outlier
                // is more often a misfiled payment than a real spike.
                Text("Well off the median — worth checking it belongs to this bill.")
                    .font(.caption2)
                    .foregroundStyle(Color.wren.alert)
            }
        }
    }
}
