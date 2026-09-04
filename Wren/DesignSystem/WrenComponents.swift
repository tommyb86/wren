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
/// block behind the element, shifted down and right. Only things you can press
/// get one, so the shadow itself reads as "tappable".
private struct WrenHardShadowModifier: ViewModifier {
    var radius: CGFloat
    var offset: CGFloat
    var isLifted: Bool

    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.wren.shadow)
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

// A ButtonStyle is not a View, so `@Environment` cannot be installed on one.
// Each style therefore hands its work to a private nested view, which can read
// the chosen theme.

/// Primary action. Highlight block, ink border, hard shadow; pressing pushes
/// the block down into its shadow.
struct WrenPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Rendered(configuration: configuration)
    }

    // Not named `Body`: that is ButtonStyle's own associated type, and a
    // private nested type cannot satisfy the protocol's requirement.
    private struct Rendered: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.wrenTheme) private var theme

        var body: some View {
            configuration.label
                .font(WrenFont.button)
                .foregroundStyle(theme.onHighlight)
                .padding(.vertical, Space.m)
                .padding(.horizontal, Space.l)
                .frame(maxWidth: .infinity)
                .wrenBox(fill: theme.highlight)
                .offset(x: configuration.isPressed ? Stroke.shadow : 0, y: configuration.isPressed ? Stroke.shadow : 0)
                .wrenHardShadow(isLifted: !configuration.isPressed)
                .animation(.snappy(duration: 0.12), value: configuration.isPressed)
        }
    }
}

/// Inline action on a row — "Paid", "Scan". Same construction as the primary
/// button at caption size, so the two read as one family. Passing nil for the
/// colours means "use the theme".
struct WrenCompactButtonStyle: ButtonStyle {
    var fill: Color? = nil
    var foreground: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        Rendered(configuration: configuration, fill: fill, foreground: foreground)
    }

    private struct Rendered: View {
        let configuration: ButtonStyleConfiguration
        let fill: Color?
        let foreground: Color?
        @Environment(\.wrenTheme) private var theme

        var body: some View {
            configuration.label
                .font(WrenFont.caption)
                .textCase(.uppercase)
                .foregroundStyle(foreground ?? theme.onHighlight)
                .padding(.vertical, Space.s)
                .padding(.horizontal, Space.m)
                .wrenBox(radius: Radius.chip, fill: fill ?? theme.highlight)
                .offset(x: configuration.isPressed ? Stroke.shadow : 0, y: configuration.isPressed ? Stroke.shadow : 0)
                .wrenHardShadow(radius: Radius.chip, isLifted: !configuration.isPressed)
                .animation(.snappy(duration: 0.12), value: configuration.isPressed)
        }
    }
}

/// A square tick box as a readout. No shadow, because a shadow in this look
/// means "you can press this" — see `WrenCheckbox` for the control.
struct WrenTickBox: View {
    enum Fill {
        case empty
        /// Settled, but not verified — an assumed direct debit.
        case assumed
        case done
    }

    var fill: Fill
    var size: CGFloat = 22

    @Environment(\.wrenTheme) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(fill == .done ? theme.highlight : Color.wren.surface)
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(
                        fill == .assumed ? Color.wren.textSecondary : Color.wren.textPrimary,
                        lineWidth: Stroke.border
                    )
            )
            .overlay {
                if fill != .empty {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.55, weight: .black))
                        .foregroundStyle(fill == .done ? theme.onHighlight : Color.wren.textSecondary)
                }
            }
    }
}

/// The tick box as a control: a hard shadow marks it pressable, and the hit
/// area is the full 44pt whatever the box draws at.
struct WrenCheckbox: View {
    var isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            WrenTickBox(fill: isOn ? .done : .empty, size: 24)
                .wrenHardShadow(radius: 2)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// A bordered meter: ink fill in an ink-ruled track. Magnitude by length only,
/// so it never needs a second colour.
struct WrenMeter: View {
    /// 0...1.
    let fraction: Double
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Color.wren.textPrimary)
                .frame(width: max(geometry.size.width * min(max(fraction, 0), 1), 2))
        }
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.wren.background)
        .overlay(Rectangle().strokeBorder(Color.wren.textPrimary, lineWidth: 1))
    }
}

// MARK: - Type and labels

/// Screen title: bold, tight-tracked sans. Big type carries the look now that
/// the serif is gone.
struct WrenTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(WrenFont.title)
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
            .font(WrenFont.label)
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

/// A small bordered tag. The theme highlight by default; pass
/// `fill: .wren.surface` for a quiet one.
struct WrenChip: View {
    let text: String
    var tint: Color? = nil
    var fill: Color? = nil

    @Environment(\.wrenTheme) private var theme

    var body: some View {
        Text(text)
            .font(WrenFont.caption)
            .monospacedDigit()
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(tint ?? theme.onHighlight)
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs)
            .wrenBox(radius: Radius.chip, fill: fill ?? theme.highlight)
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

/// The app's mark, framed as a bordered tile like everything else here.
///
/// The artwork is opaque RGB with its paper background baked in, so it cannot
/// float on a dark surface without showing a pale square. Framing it as a
/// deliberate tile — a bookplate, a stamp — is honest about that and reads as
/// intentional in both themes.
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
