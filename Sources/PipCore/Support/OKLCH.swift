import Foundation

/// The design specifies every tint in OKLCH. This converts to gamma-encoded
/// sRGB so colors match the prototype instead of being hand-approximated.
public struct OKLCH: Equatable, Sendable {
    public var l: Double, c: Double, h: Double, alpha: Double

    public init(_ l: Double, _ c: Double, _ h: Double, alpha: Double = 1) {
        self.l = l; self.c = c; self.h = h; self.alpha = alpha
    }

    /// Components in 0...1, clamped into the sRGB gamut.
    public var sRGB: (r: Double, g: Double, b: Double) {
        let hr = h * .pi / 180
        let a = c * cos(hr), b = c * sin(hr)
        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b
        let L = l_ * l_ * l_, M = m_ * m_ * m_, S = s_ * s_ * s_
        let r = 4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S
        let g = -1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S
        let bl = -0.0041960863 * L - 0.7034186147 * M + 1.7076147010 * S
        func encode(_ x: Double) -> Double {
            let v = x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
            return min(1, max(0, v))
        }
        return (encode(r), encode(g), encode(bl))
    }
}
