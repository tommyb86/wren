import SwiftUI
import WrenCore

/// Display data for one agenda row, resolved from the models by TodayView.
/// `TodayItem` carries only an id and a kind, so the name, colour and action all
/// get attached here.
struct TodayRowModel: Identifiable {
    let item: TodayItem
    let title: String
    let detail: String
    /// Bin lid colour; nil for tasks and bills.
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
            if let tint = model.tint {
                WrenLidSwatch(color: tint)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(model.title)
                    .font(.body.weight(.bold))
                    .foregroundStyle(Color.wren.textPrimary)
                Text(model.detail)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(item.isOverdue ? Color.wren.alert : Color.wren.textSecondary)
            }

            Spacer(minLength: Space.s)

            if let action = model.action {
                switch item.kind {
                case .bill:
                    Button("Paid", action: action)
                        .buttonStyle(WrenCompactButtonStyle())
                        .accessibilityLabel("Record a payment")
                        .padding(.vertical, Space.xs)
                case .task, .bin:
                    WrenCheckbox(isOn: false, action: action)
                        .accessibilityLabel("Mark done")
                }
            }
        }
        .padding(.vertical, Space.xs)
        .contentShape(.rect)
    }
}
