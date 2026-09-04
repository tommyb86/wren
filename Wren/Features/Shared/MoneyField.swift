import SwiftUI
import WrenCore

/// Money input. Holds text while editing — because a half-typed "12." isn't a
/// number — and commits to `Int` cents. Nothing downstream ever sees a
/// floating-point dollar amount.
///
/// Set large, with the sign outside the field: on a bill or a payment the
/// amount is the point of the screen, so it gets to look like it.
@MainActor
struct MoneyField: View {
    let label: String
    @Binding var cents: Int
    var placeholder: String = "0.00"
    /// Shown to the right of the amount, e.g. "estimate".
    var note: String? = nil

    @State private var text: String = ""
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            WrenFieldLabel(text: label)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("$")
                    .font(WrenFont.title2)
                    .foregroundStyle(isValid ? Color.wren.textPrimary : Color.wren.alert)
                TextField(placeholder, text: $text)
                    .font(WrenFont.title2)
                    .monospacedDigit()
                    .keyboardType(.decimalPad)
                    .foregroundStyle(isValid ? Color.wren.textPrimary : Color.wren.alert)
                    .tint(Color.wren.textPrimary)
                if let note {
                    Text(note)
                        .font(WrenFont.detail)
                        .foregroundStyle(Color.wren.textSecondary)
                }
            }
        }
        .padding(.vertical, Space.xs)
        .task {
            guard !didLoad else { return }
            didLoad = true
            // Seed from the model, but leave a genuinely zero amount blank so the
            // placeholder does the talking. No symbol: the field draws its own,
            // and seeding one gave "$$1183.07".
            text = cents == 0 ? "" : Money.plainFormat(cents: cents, showsSymbol: false)
        }
        .onChange(of: text) { _, new in
            if let parsed = Money.parse(new) { cents = parsed }
        }
    }

    private var isValid: Bool {
        text.isEmpty || Money.parse(text) != nil
    }
}
