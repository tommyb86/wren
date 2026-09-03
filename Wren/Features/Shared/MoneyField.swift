import SwiftUI
import WrenCore

/// Money input. Holds text while editing — because a half-typed "12." isn't a
/// number — and commits to `Int` cents. Nothing downstream ever sees a
/// floating-point dollar amount.
@MainActor
struct MoneyField: View {
    let label: String
    @Binding var cents: Int
    var placeholder: String = "0.00"

    @State private var text: String = ""
    @State private var didLoad = false

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(Color.wren.textPrimary)
            Spacer()
            TextField(placeholder, text: $text)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .keyboardType(.decimalPad)
                .foregroundStyle(isValid ? Color.wren.textPrimary : Color.wren.alert)
                .onChange(of: text) { _, new in
                    if let parsed = Money.parse(new) { cents = parsed }
                }
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            // Seed from the model, but leave a genuinely zero amount blank so the
            // placeholder does the talking.
            text = cents == 0 ? "" : Money.plainFormat(cents: cents)
        }
    }

    private var isValid: Bool {
        text.isEmpty || Money.parse(text) != nil
    }
}
