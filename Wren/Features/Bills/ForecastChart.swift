import SwiftUI
import WrenCore

/// Twelve months of expected cost, so the lumpy months — rego, insurance — are
/// visible before they arrive.
///
/// One measure over time, so: bars, one axis, a single series and therefore no
/// legend (the title names it). Magnitude is carried by height alone. Colouring
/// the expensive months differently would both encode by rank and spend the
/// terracotta that this app reserves for overdue, so instead the average sits
/// behind the bars as a recessive reference line.
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
            // Reference line, deliberately recessive.
            if averageCents > 0 {
                VStack(spacing: 0) {
                    Spacer()
                    Rectangle()
                        .fill(Color.wren.divider)
                        .frame(height: 1)
                        .padding(.bottom, plotHeight * CGFloat(averageCents) / CGFloat(maxCents))
                }
            }

            HStack(alignment: .bottom, spacing: 2) { // 2px surface gap between bars
                ForEach(months) { month in
                    bar(month)
                }
            }
        }
        .frame(height: plotHeight)
    }

    private func bar(_ month: ForecastMonth) -> some View {
        let isSelected = selection?.monthStart == month.monthStart
        let height = plotHeight * CGFloat(month.totalCents) / CGFloat(maxCents)

        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            // 4px rounded data-end, anchored square to the baseline.
            UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4)
                .fill(Color.wren.accent.opacity(isSelected ? 1 : 0.72))
                .frame(height: max(height, month.totalCents > 0 ? 2 : 0))
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
                Text(monthInitial(month.monthStart))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(
                        selection?.monthStart == month.monthStart
                            ? Color.wren.textPrimary
                            : Color.wren.textSecondary
                    )
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
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.wren.textPrimary)
                    Text(Money.format(cents: highlighted.totalCents))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Color.wren.textPrimary)
                    if selection == nil {
                        Text("· highest")
                            .font(.caption)
                            .foregroundStyle(Color.wren.textSecondary)
                    }
                    Spacer()
                    if averageCents > 0 {
                        Text("avg \(Money.formatWholeDollars(cents: averageCents))")
                            .font(.caption)
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
