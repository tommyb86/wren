import SwiftUI

/// Design tokens, resolved from the hand-written colour sets in Assets.xcassets.
/// Views never reference a raw hex — they go through `Color.wren`.
struct WrenPalette {
    let background = Color("Colors/Background", bundle: .main)
    let surface = Color("Colors/Surface", bundle: .main)
    let textPrimary = Color("Colors/TextPrimary", bundle: .main)
    let textSecondary = Color("Colors/TextSecondary", bundle: .main)
    let accent = Color("Colors/Accent", bundle: .main)
    let accentSoft = Color("Colors/AccentSoft", bundle: .main)
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
    static let card: CGFloat = 12
    static let chip: CGFloat = 8
}
