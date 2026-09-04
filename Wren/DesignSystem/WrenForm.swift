import SwiftUI

// Form rows for the bordered section boxes. Every field is two lines — a small
// uppercase label over the value — so a filled-in form reads as a document
// rather than a settings screen. Rows are meant to be placed inside a `List`
// section and given `.wrenRow(first:last:)`.

/// One option in a `WrenMenuRow`.
struct WrenOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String

    var id: Value { value }

    init(_ value: Value, _ title: String) {
        self.value = value
        self.title = title
    }
}

/// The small uppercase label that names a field.
struct WrenFieldLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(WrenFont.fieldLabel)
            .tracking(1)
            .textCase(.uppercase)
            .foregroundStyle(Color.wren.textSecondary)
    }
}

/// A text field with its label above it.
struct WrenTextRow: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var isMultiline: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            WrenFieldLabel(text: label)
            if isMultiline {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(2...5)
                    .font(WrenFont.heading)
                    .foregroundStyle(Color.wren.textPrimary)
                    .tint(Color.wren.textPrimary)
            } else {
                TextField(placeholder, text: $text)
                    .font(WrenFont.heading)
                    .foregroundStyle(Color.wren.textPrimary)
                    .tint(Color.wren.textPrimary)
            }
        }
        .padding(.vertical, Space.xs)
    }
}

/// The bordered switch: a lime track when on, with a square knob that carries
/// the hard shadow because it is the part you press.
struct WrenSwitch: View {
    var isOn: Bool

    var body: some View {
        HStack(spacing: 0) {
            if isOn { Spacer(minLength: 0) }
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.wren.surface)
                .frame(width: 22, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(Color.wren.textPrimary, lineWidth: Stroke.border)
                )
                .wrenHardShadow(radius: 2, offset: 1)
            if !isOn { Spacer(minLength: 0) }
        }
        .padding(2)
        .frame(width: 52, height: 30)
        .background(
            isOn ? Color.wren.highlight : Color.wren.background,
            in: RoundedRectangle(cornerRadius: 4, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color.wren.textPrimary, lineWidth: Stroke.border)
        )
    }
}

struct WrenToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.15)) { isOn.toggle() }
        } label: {
            HStack(spacing: Space.m) {
                Text(label)
                    .font(WrenFont.value)
                    .foregroundStyle(Color.wren.textPrimary)
                Spacer(minLength: Space.s)
                WrenSwitch(isOn: isOn)
            }
            .padding(.vertical, Space.xs)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(label, isOn: $isOn)
        }
    }
}

/// A choice from a short list, opened as a menu.
struct WrenMenuRow<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let options: [WrenOption<Value>]

    private var currentTitle: String {
        options.first { $0.value == selection }?.title ?? "—"
    }

    var body: some View {
        Menu {
            ForEach(options) { option in
                Button(option.title) { selection = option.value }
            }
        } label: {
            HStack(spacing: Space.m) {
                WrenFieldLabel(text: label)
                Spacer(minLength: Space.s)
                Text(currentTitle)
                    .font(WrenFont.value)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(Color.wren.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.black))
                    .foregroundStyle(Color.wren.textPrimary)
            }
            .padding(.vertical, Space.s)
            .contentShape(.rect)
        }
        .accessibilityLabel(label)
        .accessibilityValue(currentTitle)
    }
}

/// A number nudged up and down by two shadowed squares.
struct WrenStepperRow: View {
    let label: String
    let value: String
    @Binding var amount: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 3) {
                WrenFieldLabel(text: label)
                Text(value)
                    .font(WrenFont.heading)
                    .monospacedDigit()
                    .foregroundStyle(Color.wren.textPrimary)
            }
            Spacer(minLength: Space.s)
            step(systemName: "minus", enabled: amount > range.lowerBound) {
                amount = max(range.lowerBound, amount - 1)
            }
            step(systemName: "plus", enabled: amount < range.upperBound) {
                amount = min(range.upperBound, amount + 1)
            }
        }
        .padding(.vertical, Space.xs)
        .accessibilityRepresentation {
            Stepper(value: $amount, in: range) { Text(label) }
        }
    }

    private func step(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(enabled ? Color.wren.textPrimary : Color.wren.textSecondary)
                .frame(width: 34, height: 34)
                .wrenBox(radius: Radius.chip)
                .wrenHardShadow(radius: Radius.chip, isLifted: enabled)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// A native date or time picker, which stays native on purpose: a hand-built
/// calendar is a lot of surface to maintain for very little gain.
struct WrenDateRow: View {
    let label: String
    @Binding var date: Date
    var components: DatePickerComponents = [.date, .hourAndMinute]

    var body: some View {
        HStack(spacing: Space.m) {
            WrenFieldLabel(text: label)
            Spacer(minLength: Space.s)
            DatePicker("", selection: $date, displayedComponents: components)
                .labelsHidden()
                .tint(Color.wren.textPrimary)
        }
        .padding(.vertical, Space.xs)
        .accessibilityLabel(label)
    }
}

/// Tappable suggestion pills — a shortcut into a field that stays free text.
struct WrenSuggestionRow: View {
    let label: String
    let suggestions: [String]
    let onPick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            WrenFieldLabel(text: label)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            onPick(suggestion)
                        } label: {
                            Text(suggestion)
                                .font(WrenFont.caption)
                                .foregroundStyle(Color.wren.textPrimary)
                                .padding(.horizontal, Space.s)
                                .padding(.vertical, 5)
                                .wrenBox(radius: Radius.chip)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, Space.xs)
    }
}

/// The one red thing in a form. Outlined rather than filled, so deleting is
/// available without being the loudest object on the screen.
struct WrenDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(WrenFont.caption)
            .textCase(.uppercase)
            .foregroundStyle(Color.wren.alert)
            .padding(.vertical, Space.m)
            .frame(maxWidth: .infinity)
            .background(Color.wren.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.wren.alert, lineWidth: Stroke.border)
            )
            .offset(x: configuration.isPressed ? Stroke.shadow : 0, y: configuration.isPressed ? Stroke.shadow : 0)
            .background {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color.wren.alert)
                    .offset(x: configuration.isPressed ? 0 : Stroke.shadow, y: configuration.isPressed ? 0 : Stroke.shadow)
            }
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}

/// The Save action in a sheet's navigation bar: a small lime block.
struct WrenToolbarButton: View {
    let title: String
    var isEnabled: Bool = true

    var body: some View {
        Text(title)
            .font(WrenFont.caption)
            .textCase(.uppercase)
            .foregroundStyle(isEnabled ? Color.wren.onHighlight : Color.wren.textSecondary)
            .padding(.horizontal, Space.m)
            .frame(height: 30)
            .wrenBox(radius: Radius.chip, fill: isEnabled ? .wren.highlight : .wren.surface)
            .wrenHardShadow(radius: Radius.chip, isLifted: isEnabled)
    }
}

/// A live readout of what the form adds up to. Pale lime, because it is the
/// consequence of the choices above rather than a control.
struct WrenOutcomeBox: View {
    let label: String
    let value: String
    var unit: String? = nil
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            WrenFieldLabel(text: label)
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Text(value)
                    .font(WrenFont.title2)
                    .monospacedDigit()
                    .foregroundStyle(Color.wren.textPrimary)
                if let unit {
                    Text(unit)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.wren.textPrimary)
                }
            }
            if let detail {
                Text(detail)
                    .font(WrenFont.detail)
                    .monospacedDigit()
                    .foregroundStyle(Color.wren.textPrimary)
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wrenBox(fill: .wren.accentSoft)
    }
}
