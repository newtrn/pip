import CoreGraphics
import Foundation

/// Port of the morphing blob from the design's `slime.js`. All coordinates are
/// in the design's 24×24 viewBox; the renderer scales them.
public enum SlimeGeometry {
    /// Ground line the slime sits on.
    public static let ground: Double = 21.6
    static let pointCount = 14

    public struct Blob {
        public let path: CGPath
        public let cy: Double
        public let ry: Double
        public let rx: Double
        public let top: Double
    }

    /// Current animated shape parameters (eased toward a `SlimeShapeTarget`).
    public struct Params: Equatable, Sendable {
        public var sx: Double, sy: Double, amp: Double, spd: Double
        public init(sx: Double, sy: Double, amp: Double, spd: Double) {
            self.sx = sx; self.sy = sy; self.amp = amp; self.spd = spd
        }
        public init(_ t: SlimeShapeTarget) { self.init(sx: t.sx, sy: t.sy, amp: t.amp, spd: t.spd) }
    }

    public static func blob(_ p: Params, t: Double) -> Blob {
        let br = sin(t * p.spd * 1.1) * 0.035 * (0.4 + p.amp)
        let ry = 8.6 * p.sy * (1 + br)
        let rx = 9.2 * p.sx * (1 - br * 0.8)
        let cy = ground - ry
        var pts: [CGPoint] = []
        pts.reserveCapacity(pointCount)
        for i in 0..<pointCount {
            let a = Double(i) / Double(pointCount) * .pi * 2
            let s = sin(a), c = cos(a), up = (1 - s) / 2
            let w = p.amp * up * (sin(3 * a + t * p.spd) * 0.6 + sin(2 * a - t * p.spd * 1.4 + 1) * 0.4)
            let x = 12 + c * (rx + w) * (1 + 0.14 * max(0, s))
            pts.append(CGPoint(x: x, y: min(ground, cy + s * (ry + w))))
        }
        // Closed Catmull-Rom spline through the points, as cubic Béziers.
        let path = CGMutablePath()
        let n = pts.count
        path.move(to: pts[0])
        for i in 0..<n {
            let p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n], p3 = pts[(i + 2) % n]
            path.addCurve(
                to: p2,
                control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        path.closeSubpath()
        return Blob(path: path, cy: cy, ry: ry, rx: rx, top: cy - ry - p.amp)
    }

    /// Liquid surface filling `level` (0...1) of the blob's height, with a gentle
    /// wave while animating. Clip it to the blob path when drawing.
    public static func liquid(_ b: Blob, level: Double, t: Double, animated: Bool) -> CGPath? {
        guard level > 0.001 else { return nil }
        let y = ground - (ground - b.top + 1) * level
        let amp = animated && level < 0.99 ? 0.5 : 0
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -1, y: y))
        var x = -1.0
        while x <= 25 {
            path.addLine(to: CGPoint(x: x, y: y + amp * sin(x * 0.55 + t * 2.2) + amp * 0.5 * sin(x * 1.1 - t * 1.3)))
            x += 1.5
        }
        path.addLine(to: CGPoint(x: 25, y: 26))
        path.addLine(to: CGPoint(x: -1, y: 26))
        path.closeSubpath()
        return path
    }

    /// Eye blink scale for a 5.5 s cycle: closes at 96 % of the cycle.
    public static func blinkScale(t: Double) -> Double {
        let phase = (t.truncatingRemainder(dividingBy: 5.5)) / 5.5
        if phase < 0.93 { return 1 }
        if phase < 0.96 { return 1 - 0.9 * (phase - 0.93) / 0.03 }
        return 0.1 + 0.9 * (phase - 0.96) / 0.04
    }
}
