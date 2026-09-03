import SwiftUI
import UIKit

/// Space Grotesk for anything that carries the look; the system font for
/// reading. Every display-face use goes through here so the size, weight and
/// Dynamic Type anchor are decided once.
///
/// The font ships as one variable TTF (`Wren/Fonts`, SIL OFL). iOS registers
/// its named instances, so the faces are addressed by PostScript name. If the
/// file ever fails to register, `Font.custom` falls back to the system font
/// silently — Diagnostics reports whether the family is actually installed.
enum WrenFont {
    static let family = "Space Grotesk"

    private static func face(_ weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black, .semibold: return "SpaceGrotesk-Bold"
        case .medium: return "SpaceGrotesk-Medium"
        case .light, .thin, .ultraLight: return "SpaceGrotesk-Light"
        default: return "SpaceGrotesk-Regular"
        }
    }

    static func display(_ size: CGFloat, weight: Font.Weight = .bold, relativeTo style: Font.TextStyle) -> Font {
        Font.custom(face(weight), size: size, relativeTo: style)
    }

    /// Screen title.
    static let title = display(34, relativeTo: .largeTitle)
    /// Money headlines on reports.
    static let title2 = display(28, relativeTo: .title2)
    /// Empty-state titles.
    static let title3 = display(22, relativeTo: .title3)
    /// The summary sentence on Today.
    static let sentence = display(18, weight: .medium, relativeTo: .body)
    /// Row titles and tile values.
    static let heading = display(17, relativeTo: .body)
    /// Primary buttons.
    static let button = display(17, relativeTo: .body)
    /// Uppercase section labels.
    static let label = display(15, relativeTo: .subheadline)
    /// Chips, tile labels, compact buttons.
    static let caption = display(12, relativeTo: .caption)
    /// Row and tile detail lines.
    static let detail = display(12, weight: .medium, relativeTo: .caption)

    static var isInstalled: Bool {
        UIFont.familyNames.contains(family)
    }
}
