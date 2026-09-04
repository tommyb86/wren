import SwiftUI

/// Design tokens, resolved from the hand-written colour sets in Assets.xcassets.
/// Views never reference a raw hex — they go through `Color.wren`.
///
/// The look is a calm neo-brutalism: paper and ink, one bright highlight,
/// borders instead of shadows. `textPrimary` doubles as the ink every border is
/// drawn in, and `accent` resolves to the same ink so links and ticks stay
/// monochrome.
///
/// The highlight is not here: it is the one colour the user chooses, so it
/// lives on `WrenTheme` and is read from the environment. See that file.
struct WrenPalette {
    let background = Color("Colors/Background", bundle: .main)
    let surface = Color("Colors/Surface", bundle: .main)
    let textPrimary = Color("Colors/TextPrimary", bundle: .main)
    let textSecondary = Color("Colors/TextSecondary", bundle: .main)
    let accent = Color("Colors/Accent", bundle: .main)
    let alert = Color("Colors/Alert", bundle: .main)
    let divider = Color("Colors/Divider", bundle: .main)
}

extension Color {
    static let wren = WrenPalette()
}

/// 4pt spacing scale.
enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum Radius {
    static let card: CGFloat = 6
    static let chip: CGFloat = 3
}

/// Line weights. Borders are drawn, not implied, so these are load-bearing.
enum Stroke {
    /// Every box, chip and swatch.
    static let border: CGFloat = 1.5
    /// The hard offset shadow under anything pressable.
    static let shadow: CGFloat = 2
}

// MARK: - Bin lid colours

extension Color {
    /// Bins are the deliberate exception to "ink and one highlight" — these map
    /// to physical lid colours, so they come from hex rather than the palette.
    init(binHex: String) {
        let cleaned = binHex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else {
            self = .wren.accent
            return
        }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// The lid colours a QLD kerbside actually offers.
enum BinLid: String, CaseIterable, Identifiable {
    case red = "#B4453C"
    case yellow = "#D9A82E"
    case green = "#5C8C3F"
    case blue = "#3E6E9E"
    case grey = "#7A817C"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .red: return "Red"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .blue: return "Blue"
        case .grey: return "Grey"
        }
    }

    var color: Color { Color(binHex: rawValue) }

    /// The bin this lid usually means, used as the default name on a new bin.
    var suggestedName: String {
        switch self {
        case .red: return "General waste"
        case .yellow: return "Recycling"
        case .green: return "Green waste"
        case .blue: return "Paper"
        case .grey: return "Bin"
        }
    }
}
