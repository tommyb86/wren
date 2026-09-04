import SwiftUI
import UIKit

/// The accent, and the only colour in the app the user gets to choose.
///
/// Paper, ink, hairline and alert are fixed — they carry the look and the
/// meaning of "overdue". What varies is the highlight: the fill on anything
/// pressable, the selected state, and the one figure a screen is about. Each
/// theme therefore has to supply three things that hang together: the
/// highlight, something legible on top of it, and a pale version for tints.
///
/// The highlight is the same in light and dark, because a saturated flat
/// colour reads on both paper and near-black. Only the soft tint swaps.
enum WrenTheme: String, CaseIterable, Identifiable, Sendable {
    case lime, tangerine, blossom, sky, sun, mint

    static let storageKey = "accentTheme"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lime: return "Lime"
        case .tangerine: return "Tangerine"
        case .blossom: return "Blossom"
        case .sky: return "Sky"
        case .sun: return "Sun"
        case .mint: return "Mint"
        }
    }

    /// The fill on anything pressable or selected.
    var highlight: Color {
        switch self {
        case .lime: return Self.fixed("C6F135")
        case .tangerine: return Self.fixed("FF7A29")
        case .blossom: return Self.fixed("FF6BAA")
        case .sky: return Self.fixed("4D7CFF")
        case .sun: return Self.fixed("FFC61A")
        case .mint: return Self.fixed("35E0C0")
        }
    }

    /// Text and glyphs drawn on `highlight`. Ink on everything but Sky, which
    /// is dark enough to need paper on top.
    var onHighlight: Color {
        switch self {
        case .sky: return Self.fixed("FFFFFF")
        default: return Self.fixed("111111")
        }
    }

    /// The pale tint: suggestion pills, the outcome box, thumbnail placeholders.
    /// This is the one that has to swap between appearances, since a pale wash
    /// on paper becomes a deep one on near-black.
    var soft: Color {
        switch self {
        case .lime: return Self.dynamic(light: "E7F7B0", dark: "3A4410")
        case .tangerine: return Self.dynamic(light: "FFE0CC", dark: "4A2410")
        case .blossom: return Self.dynamic(light: "FFD9E8", dark: "47182F")
        case .sky: return Self.dynamic(light: "DCE5FF", dark: "17224A")
        case .sun: return Self.dynamic(light: "FFEEBC", dark: "443608")
        case .mint: return Self.dynamic(light: "C8F6EE", dark: "0E4038")
        }
    }

    // MARK: - Colour building

    private static func fixed(_ hex: String) -> Color {
        Color(uiColor: UIColor(wrenHex: hex))
    }

    private static func dynamic(light: String, dark: String) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(wrenHex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    /// Six hex digits, no alpha. Themes are defined in code rather than as
    /// colour sets because the user picks between them at runtime, and an
    /// asset catalogue can only answer one name with one colour.
    convenience init(wrenHex: String) {
        let cleaned = wrenHex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        let value = Int(cleaned, radix: 16) ?? 0
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Environment

private struct WrenThemeKey: EnvironmentKey {
    static let defaultValue: WrenTheme = .lime
}

extension EnvironmentValues {
    /// Read this rather than reaching for a global: the theme changes while the
    /// app is running, and only an environment read makes a view redraw.
    var wrenTheme: WrenTheme {
        get { self[WrenThemeKey.self] }
        set { self[WrenThemeKey.self] = newValue }
    }
}
