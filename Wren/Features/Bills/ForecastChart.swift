import SwiftUI
import WrenCore

/// Twelve months of expected cost, so the lumpy months — rego, insurance — are
/// visible before they arrive.
///
/// One measure over time, so: bars, one axis, a single series and therefore no
/// legend (the title names it). Magnitude is carried by height alone. Bars are
/// solid ink with square ends; lime marks the selected month only, which is
/// the same rule the rest of the app follows — lime means you pressed it.
@MainActor
struct ForecastChart: View {
    let months: [ForecastMonth]
    var calendar: Calendar = .current
    @Binding var selection: ForecastMonth?

    private var maxCents: Int {
        max(months.map(\.totalCents).max() ?? 0, 1)
    }

    private var averageCents: Int {
        BillReports.averageMonthlyCents(months)
    }

    private let plotHeight: CGFloat = 132

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            plot
            axis
            caption
        }
    }

    private var plot: some View {
        ZStack(alignment: .bottom) {
            // Reference line, dashed so it reads as an annotation rather than
            // as data.
            if averageCents > 0 {
                VStack(spacing: 0) {
                    Spacer()
                    DashedRule()
                        .stroke(
                            Color.wren.textSecondary,
                            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                        )
                        .frame(height: 1)
                        .padding(.bottom, plotHeight * CGFloat(averageCents) / CGFloat(maxCents))
                }
            }

            HStack(alignment: .bottom, spacing: 2) {
                ForEach(months) { month in
                    bar(month)
                }
            }
        }
        .frame(height: plotHeight)
        // The baseline is a real rule, not an implied one.
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.wren.textPrimary)
                .frame(height: Stroke.border)
        }
    }

    private func bar(_ month: ForecastMonth) -> some View {
        let isSelected = selection?.monthStart == month.monthStart
        let height = plotHeight * CGFloat(month.totalCents) / CGFloat(maxCents)

        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            Rectangle()
                .fill(isSelected ? Color.wren.highlight : Color.wren.textPrimary)
                .frame(height: max(height, month.totalCents > 0 ? 2 : 0))
                .overlay {
                    if isSelected {
                        Rectangle().strokeBorder(Color.wren.textPrimary, lineWidth: Stroke.border)
                    }
                }
        }
        .frame(maxWidth: .infinity)
        .frame(height: plotHeight)
        .contentShape(.rect) // hit target is the whole column, not just the bar
        .onTapGesture {
            withAnimation(.snappy(duration: 0.2)) {
                selection = isSelected ? nil : month
            }
        }
        .accessibilityLabel(
            "\(month.monthStart.formatted(.dateTime.month(.wide).year())): "
                + Money.formatWholeDollars(cents: month.totalCents)
        )
    }

    private var axis: some View {
        HStack(spacing: 2) {
            ForEach(months) { month in
                let isSelected = selection?.monthStart == month.monthStart
                Text(monthInitial(month.monthStart))
                    .font(.caption2.weight(isSelected ? .black : .medium))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Color.wren.textPrimary : Color.wren.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Direct labels are selective — the selected month, or the peak when
    /// nothing is selected. Never a number on every bar.
    private var caption: some View {
        let highlighted = selection ?? months.max { $0.totalCents < $1.totalCents }

        return Group {
            if let highlighted {
                HStack(spacing: Space.xs) {
                    Text(highlighted.monthStart.formatted(.dateTime.month(.wide).year()))
                        .font(WrenFont.detail)
                        .foregroundStyle(Color.wren.textPrimary)
                    Text(Money.format(cents: highlighted.totalCents))
                        .font(WrenFont.detail)
                        .monospacedDigit()
                        .foregroundStyle(Color.wren.textPrimary)
                    if selection == nil {
                        Text("· highest")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.wren.textSecondary)
                    }
                    Spacer(minLength: Space.xs)
                    if averageCents > 0 {
                        Text("avg \(Money.formatWholeDollars(cents: averageCents))")
                            .font(.caption2.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(Color.wren.textSecondary)
                    }
                }
            }
        }
    }

    private func monthInitial(_ date: Date) -> String {
        let symbols = calendar.veryShortMonthSymbols
        let index = calendar.component(.month, from: date) - 1
        return symbols.indices.contains(index) ? symbols[index] : "?"
    }
}

/// A horizontal rule that can carry a dash pattern. `Rectangle` cannot, since a
/// filled shape has no stroke to dash.
private struct DashedRule: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        }
    }
}
