import SwiftUI

/// A card: surface fill, hairline border, no shadow.
struct WrenCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.wren.surface, in: RoundedRectangle(cornerRadius: Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(Color.wren.divider, lineWidth: 1)
            )
    }
}

/// Primary action. Sage fill, generous tap target.
struct WrenPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(Color.wren.surface)
            .padding(.vertical, Space.m)
            .padding(.horizontal, Space.l)
            .frame(maxWidth: .infinity)
            .background(Color.wren.accent, in: RoundedRectangle(cornerRadius: Radius.card))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// Serif screen title over sans body — the thing that stops it reading as a template.
struct WrenTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.largeTitle, design: .serif))
            .foregroundStyle(Color.wren.textPrimary)
    }
}

struct WrenChip: View {
    let text: String
    var tint: Color = Color.wren.accent

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs)
            .background(Color.wren.accentSoft, in: RoundedRectangle(cornerRadius: Radius.chip))
    }
}

/// The app's mark, framed the way iOS frames it on the home screen.
///
/// The artwork is opaque RGB with its warm-paper background baked in, so it
/// cannot float on a dark surface without showing a pale square. Presenting it
/// deliberately as a tile — a bookplate, a stamp — is honest about that and
/// reads as intentional in both themes.
struct WrenMark: View {
    var size: CGFloat = 60

    var body: some View {
        Image("WrenMark")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            // Matches the iOS icon mask closely enough to read as the same object.
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .strokeBorder(Color.wren.divider, lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}
