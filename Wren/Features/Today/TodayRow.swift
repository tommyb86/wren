import SwiftUI
import WrenCore

/// Display data for one agenda row, resolved from the models by TodayView.
/// `TodayItem` carries only an id and a kind, so the name, colour and action all
/// get attached here.
struct TodayRowModel: Identifiable {
    let item: TodayItem
    let title: String
    let detail: String
    /// Bin lid colour; nil for tasks and bills, which use the palette.
    let tint: Color?
    let action: (() -> Void)?

    var id: String { item.id }
}

@MainActor
struct TodayRow: View {
    let model: TodayRowModel
    var calendar: Calendar = .current

    private var item: TodayItem { model.item }

    var body: some View {
        HStack(spacing: Space.m) {
            marker

            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.wren.textPrimary)
                Text(model.detail)
                    .font(.caption)
                    .foregroundStyle(item.isOverdue ? Color.wren.alert : Color.wren.textSecondary)
            }

            Spacer()

            if let amountCents = item.amountCents {
                Text(Money.format(cents: amountCents))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.wren.textSecondary)
            }

            if let action = model.action {
                Button(action: action) {
                    Image(systemName: item.kind == .bill ? "plus.circle" : "circle")
                        .font(.title3)
                        .foregroundStyle(Color.wren.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.kind == .bill ? "Record a payment" : "Mark done")
            }
        }
        .padding(.vertical, Space.xs)
        .contentShape(.rect)
    }

    /// Bins get their lid colour as a bar — they map to a physical object.
    /// Tasks and bills get a glyph, since a symbol reads faster than a swatch
    /// when there's nothing to colour-match against.
    @ViewBuilder
    private var marker: some View {
        if let tint = model.tint {
            RoundedRectangle(cornerRadius: 3)
                .fill(tint)
                .frame(width: 6, height: 34)
        } else {
            Image(systemName: item.kind == .task ? "checklist" : "banknote")
                .font(.caption)
                .foregroundStyle(item.isOverdue ? Color.wren.alert : Color.wren.textSecondary)
                .frame(width: 20)
        }
    }
}
