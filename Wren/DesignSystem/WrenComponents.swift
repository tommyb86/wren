import SwiftUI

// MARK: - Surfaces

/// Bordered surface, no shadow: the container for nearly everything.
private struct WrenBoxModifier: ViewModifier {
    var radius: CGFloat
    var fill: Color

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.wren.textPrimary, lineWidth: Stroke.border)
            )
    }
}

/// The hard offset shadow that does the work a drop shadow used to: a solid
/// block of ink behind the element, shifted down and right. Only things you
/// can press get one, so the shadow itself reads as "tappable".
private struct WrenHardShadowModifier: ViewModifier {
    var radius: CGFloat
    var offset: CGFloat
    var isLifted: Bool

    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.wren.textPrimary)
                .offset(x: isLifted ? offset : 0, y: isLifted ? offset : 0)
        }
    }
}

extension View {
    func wrenBox(radius: CGFloat = Radius.card, fill: Color = .wren.surface) -> some View {
        modifier(WrenBoxModifier(radius: radius, fill: fill))
    }

    func wrenHardShadow(radius: CGFloat = Radius.card, offset: CGFloat = Stroke.shadow, isLifted: Bool = true) -> some View {
        modifier(WrenHardShadowModifier(radius: radius, offset: offset, isLifted: isLifted))
    }
}

/// A card: surface fill, ink border, no shadow.
struct WrenCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .wrenBox()
    }
}

// MARK: - Buttons

/// Primary action. Lime block, ink border, hard shadow; pressing pushes the
/// block down into its shadow.
struct WrenPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.bold))
            .foregroundStyle(Color.wren.onHighlight)
            .padding(.vertical, Space.m)
            .padding(.horizontal, Space.l)
            .frame(maxWidth: .infinity)
            .wrenBox(fill: .wren.highlight)
            .offset(x: configuration.isPressed ? Stroke.shadow : 0, y: configuration.isPressed ? Stroke.shadow : 0)
            .wrenHardShadow(isLifted: !configuration.isPressed)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}

/// Inline action on a row — "Paid", "Scan". Same construction as the primary
/// button at caption size, so the two read as one family.
struct WrenCompactButtonStyle: ButtonStyle {
    var fill: Color = .wren.highlight
    var foreground: Color = .wren.onHighlight

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(foreground)
            .padding(.vertical, Space.s)
            .padding(.horizontal, Space.m)
            .wrenBox(radius: Radius.chip, fill: fill)
            .offset(x: configuration.isPressed ? Stroke.shadow : 0, y: configuration.isPressed ? Stroke.shadow : 0)
            .wrenHardShadow(radius: Radius.chip, isLifted: !configuration.isPressed)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}

/// A square tick box with a hard shadow. `isOn` fills it lime; the hit area
/// is the full 44pt whatever the box draws at.
struct WrenCheckbox: View {
    var isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(isOn ? Color.wren.highlight : Color.wren.surface)
                .frame(width: 24, height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(Color.wren.textPrimary, lineWidth: Stroke.border)
                )
                .overlay {
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(Color.wren.onHighlight)
                    }
                }
                .wrenHardShadow(radius: 2)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Type and labels

/// Screen title: bold, tight-tracked sans. Big type carries the look now that
/// the serif is gone.
struct WrenTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.largeTitle, design: .default, weight: .bold))
            .tracking(-0.8)
            .foregroundStyle(Color.wren.textPrimary)
    }
}

/// Uppercase, tracked section label.
struct WrenSectionLabel: View {
    let text: String
    var color: Color = .wren.textPrimary

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.bold))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

/// A small bordered tag. Lime by default; pass `fill: .wren.surface` for a
/// quiet one.
struct WrenChip: View {
    let text: String
    var tint: Color = Color.wren.onHighlight
    var fill: Color = Color.wren.highlight

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(tint)
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs)
            .wrenBox(radius: Radius.chip, fill: fill)
    }
}

/// A bin lid colour as a bordered square, so it reads as an object rather
/// than a status dot.
struct WrenLidSwatch: View {
    let color: Color
    var size: CGFloat = 14

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(Color.wren.textPrimary, lineWidth: Stroke.border)
            )
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
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.wren.textPrimary, lineWidth: Stroke.border)
            )
            .accessibilityHidden(true)
    }
}
