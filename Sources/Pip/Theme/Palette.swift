import PipCore
import SwiftUI

extension Color {
    init(oklch l: Double, _ c: Double, _ h: Double, opacity: Double = 1) {
        let rgb = OKLCH(l, c, h).sRGB
        self.init(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: opacity)
    }

    /// CSS-style `rgba(r,g,b,a)` with 0–255 channels.
    init(rgba r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.init(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a)
    }

    init(hex: UInt32) {
        self.init(rgba: Double((hex >> 16) & 0xFF), Double((hex >> 8) & 0xFF), Double(hex & 0xFF))
    }
}

/// Usage colors from the prototype (`lc`, `pc`, `lcLight`). They depend on the
/// provider hue and on how much is left, and brighten slightly in Dark Mode.
struct Palette {
    var dark: Bool

    /// Liquid / number color: red when nearly empty, amber when low, otherwise the provider hue.
    func level(_ remaining: Int, hue: Double) -> Color {
        let d = dark ? 0.05 : 0
        if remaining <= 5 { return Color(oklch: 0.64 + d, 0.18, 25) }
        if remaining <= 25 { return Color(oklch: 0.76 + d, 0.15, 70) }
        return Color(oklch: 0.68 + d, 0.14, hue)
    }

    /// Lighter top stop of the liquid gradient.
    func levelLight(_ remaining: Int, hue: Double) -> Color {
        let d = dark ? 0.03 : 0
        if remaining <= 5 { return Color(oklch: 0.8 + d, 0.12, 45) }
        if remaining <= 25 { return Color(oklch: 0.9 + d, 0.1, 95) }
        return Color(oklch: 0.86 + d, 0.09, hue + 25)
    }

    /// Provider identity color, independent of usage.
    func provider(_ hue: Double) -> Color {
        Color(oklch: dark ? 0.74 : 0.66, 0.14, hue)
    }

    /// Color for a value given the "Numbers show" setting: when showing usage,
    /// warning colors would be misleading, so the provider color is used.
    func value(remaining: Int?, hue: Double, showUsed: Bool) -> Color {
        guard let remaining, !showUsed else { return provider(hue) }
        return level(remaining, hue: hue)
    }

    var ink: Color { dark ? Color(hex: 0xF6F3EE) : Color(hex: 0x2B2622) }

    static let good = Color(oklch: 0.66, 0.15, 150)
    static let warn = Color(oklch: 0.76, 0.15, 70)
    static let bad = Color(oklch: 0.64, 0.18, 25)
    static let droplet = Color(oklch: 0.78, 0.1, 230)
}

/// Popover tokens (`pt` in the prototype).
struct PopoverTokens {
    let bg, fg, sub, hair, card, edge, rim, track, tabOn, segOff: Color

    static func of(dark: Bool) -> PopoverTokens {
        dark
            ? .init(bg: Color(rgba: 40, 40, 43, 0.82), fg: Color(hex: 0xF5F5F7), sub: Color(rgba: 245, 245, 247, 0.58),
                    hair: Color(rgba: 255, 255, 255, 0.09), card: Color(rgba: 255, 255, 255, 0.07), edge: Color(rgba: 0, 0, 0, 0.6),
                    rim: Color(rgba: 255, 255, 255, 0.12), track: Color(rgba: 255, 255, 255, 0.1), tabOn: Color(rgba: 255, 255, 255, 0.14),
                    segOff: Color(rgba: 255, 255, 255, 0.1))
            : .init(bg: Color(rgba: 251, 250, 248, 0.86), fg: Color(hex: 0x1D1B19), sub: Color(rgba: 29, 27, 25, 0.56),
                    hair: Color(rgba: 0, 0, 0, 0.08), card: Color(rgba: 0, 0, 0, 0.045), edge: Color(rgba: 0, 0, 0, 0.16),
                    rim: Color(rgba: 255, 255, 255, 0.7), track: Color(rgba: 0, 0, 0, 0.07), tabOn: .white,
                    segOff: Color(rgba: 0, 0, 0, 0.08))
    }
}

/// Settings window tokens (`pf` in the prototype).
struct PrefTokens {
    let fg, sub, hair, card, btn: Color

    static func of(dark: Bool) -> PrefTokens {
        dark
            ? .init(fg: Color(hex: 0xF2F2F4), sub: Color(rgba: 242, 242, 244, 0.55), hair: Color(rgba: 255, 255, 255, 0.1),
                    card: Color(rgba: 255, 255, 255, 0.04), btn: Color(rgba: 255, 255, 255, 0.1))
            : .init(fg: Color(hex: 0x1D1B19), sub: Color(rgba: 29, 27, 25, 0.55), hair: Color(rgba: 0, 0, 0, 0.1),
                    card: .white, btn: .white)
    }
}

/// The prototype loads Instrument Serif and IBM Plex Mono from Google Fonts.
/// A native app should not fetch fonts at runtime, so the system serif (New York)
/// and monospace (SF Mono) stand in with the same roles.
enum PipFont {
    static func serif(_ size: CGFloat) -> Font { .system(size: size, design: .serif) }
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .monospaced) }
}
