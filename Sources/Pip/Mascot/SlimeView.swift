import PipCore
import SwiftUI

/// Colors for one Pip rendering. `mono` is the menu bar variant: outline only,
/// tinted liquid, drawn in the menu bar's text color.
struct SlimeStyle {
    var mono = false
    var ink: Color
    var tint: Color?
    var bodyA: Color = .clear
    var bodyB: Color = .clear
    var fillA: Color = .clear
    var fillB: Color = .clear
    var edge: Color = Color(rgba: 60, 40, 20, 0.14)
    /// Calmer motion, used where Pip sits next to other content (menu bar).
    var calm = false

    /// Full-color Pip as drawn in the popover and Touch Bar (`pip()` in the prototype).
    static func color(mood: MascotMood, remaining: Int, hue: Double, dark: Bool) -> SlimeStyle {
        let p = Palette(dark: dark)
        let grey = mood == .disconnected || mood == .stale
        return SlimeStyle(
            ink: p.ink,
            bodyA: grey ? Color(oklch: dark ? 0.4 : 0.95, 0.005, 0) : dark ? Color(oklch: 0.42, 0.05, hue) : Color(oklch: 0.97, 0.03, hue + 20),
            bodyB: grey ? Color(oklch: dark ? 0.32 : 0.88, 0.005, 0) : dark ? Color(oklch: 0.3, 0.04, hue) : Color(oklch: 0.9, 0.06, hue),
            fillA: p.levelLight(remaining, hue: hue),
            fillB: p.level(remaining, hue: hue),
            edge: dark ? Color(rgba: 255, 255, 255, 0.14) : Color(rgba: 60, 40, 20, 0.14))
    }

    static func mono(ink: Color, tint: Color?) -> SlimeStyle {
        SlimeStyle(mono: true, ink: ink, tint: tint, calm: true)
    }
}

/// Holds the eased shape between frames. The prototype eases toward each
/// mood's target with `1 - exp(-dt·3.2)`, which this reproduces.
final class SlimeAnimator {
    private var cur: SlimeGeometry.Params?
    private var level: Double = 1
    private var t = Double.random(in: 0..<20)
    private var last: Date?

    func step(to date: Date, mood: MascotMood, level target: Double, animated: Bool, calm: Bool) -> (SlimeGeometry.Params, Double, Double) {
        let goal = SlimeShapeTarget.of(mood)
        let dt = last.map { min(0.25, max(0, date.timeIntervalSince($0))) } ?? 0
        last = date
        guard animated, var p = cur else {
            let p = SlimeGeometry.Params(sx: goal.sx, sy: goal.sy, amp: goal.amp * (calm ? 0.5 : 1), spd: goal.spd * (calm ? 0.7 : 1))
            cur = p
            level = target
            return (p, target, t)
        }
        t += dt
        let k = 1 - exp(-dt * 3.2)
        p.sx += (goal.sx - p.sx) * k
        p.sy += (goal.sy - p.sy) * k
        p.amp += (goal.amp * (calm ? 0.5 : 1) - p.amp) * k
        p.spd += (goal.spd * (calm ? 0.7 : 1) - p.spd) * k
        cur = p
        level += (target - level) * (1 - exp(-dt * 2))
        return (p, level, t)
    }
}

/// Pip, the slime mascot. Drawn with Canvas and driven by a TimelineView whose
/// rate comes from `MotionController`; a nil rate renders one still frame.
struct SlimeView: View {
    var mood: MascotMood
    /// Liquid level, 0...1.
    var level: Double
    var size: CGFloat
    var style: SlimeStyle
    var fps: Double?
    /// Holds the current frame without stopping motion for good; used for the
    /// menu bar's duty-cycled animation.
    var paused = false

    @State private var animator = SlimeAnimator()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / (fps ?? 30), paused: fps == nil || paused)) { context in
            // The blob is allowed to bulge past its 24-unit box, as in the SVG (`overflow: visible`).
            Canvas { gc, _ in
                draw(in: &gc, date: context.date)
            }
            .frame(width: size * 1.5, height: size * 1.5)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func draw(in gc: inout GraphicsContext, date: Date) {
        let animated = fps != nil
        let lv = mood.hidesLiquid ? 0 : max(0, min(1, level))
        let (params, curLevel, t) = animator.step(to: date, mood: mood, level: lv, animated: animated, calm: style.calm)
        let b = SlimeGeometry.blob(params, t: t)

        gc.translateBy(x: size * 0.25, y: size * 0.25)
        gc.scaleBy(x: size / 24, y: size / 24)

        let body = Path(b.path)
        let box = body.boundingRect
        if !style.mono {
            gc.fill(body, with: .linearGradient(Gradient(colors: [style.bodyA, style.bodyB]),
                                                startPoint: CGPoint(x: box.minX, y: box.minY), endPoint: CGPoint(x: box.minX, y: box.maxY)))
        }
        if let liquid = SlimeGeometry.liquid(b, level: curLevel, t: t, animated: animated) {
            let lp = Path(liquid)
            gc.drawLayer { layer in
                layer.clip(to: body)
                if style.mono {
                    layer.fill(lp, with: .color(style.tint.map { $0.opacity(0.95) } ?? style.ink.opacity(0.3)))
                } else {
                    let lb = lp.boundingRect
                    layer.fill(lp, with: .linearGradient(Gradient(colors: [style.fillA, style.fillB]),
                                                         startPoint: CGPoint(x: lb.minX, y: lb.minY),
                                                         endPoint: CGPoint(x: lb.minX + lb.width * 0.3, y: lb.maxY)))
                }
            }
        }
        if !style.mono {
            let hx = 12 - b.rx * 0.42, hy = b.cy - b.ry * 0.5
            gc.fill(Path(ellipseIn: CGRect(x: hx - 1.8, y: hy - 1.05, width: 3.6, height: 2.1)), with: .color(.white.opacity(0.65)))
        }
        gc.stroke(body, with: .color(style.mono ? style.ink : style.edge),
                  style: StrokeStyle(lineWidth: style.mono ? 1.6 : 0.7, lineJoin: .round))

        var face = gc
        let fs = 0.8 + 0.2 * min(1, params.sy)
        let sway = animated ? 0.35 * sin(t * params.spd * 0.7) * params.amp : 0
        face.translateBy(x: 12 + sway, y: b.cy + b.ry * 0.02)
        face.scaleBy(x: fs, y: fs)
        face.translateBy(x: -12, y: -10.8)
        drawFace(in: face, t: t, blinkClock: date.timeIntervalSinceReferenceDate, animated: animated)
    }

    private func drawFace(in gc: GraphicsContext, t: Double, blinkClock: Double, animated: Bool) {
        let mono = style.mono, ink = style.ink
        let sw: CGFloat = mono ? 1.4 : 0.9
        let e: CGFloat = mono ? 1 : 0.8
        let L: CGFloat = 9.5, R: CGFloat = 14.5, Y: CGFloat = 10.8
        let stroke = StrokeStyle(lineWidth: sw, lineCap: .round, lineJoin: .round)

        var eyes = gc
        if animated && mood.blinks {
            // Wall-clock blink, so the menu bar's wake-up bursts can line up with it.
            let s = SlimeGeometry.blinkScale(t: blinkClock)
            eyes.translateBy(x: 12, y: Y)
            eyes.scaleBy(x: 1, y: s)
            eyes.translateBy(x: -12, y: -Y)
        }
        if mood == .stale { eyes.opacity = 0.45 }

        switch mood {
        case .low:
            for x in [L, R] {
                eyes.fill(Path(roundedRect: CGRect(x: x - 1.1 * e, y: Y - 0.5 * e, width: 2.2 * e, height: 1.1 * e), cornerRadius: 0.55 * e), with: .color(ink))
            }
        case .exhausted:
            var p = Path()
            p.move(to: CGPoint(x: L - 0.9 * e, y: Y - e)); p.addLine(to: CGPoint(x: L + 0.9 * e, y: Y)); p.addLine(to: CGPoint(x: L - 0.9 * e, y: Y + e))
            p.move(to: CGPoint(x: R + 0.9 * e, y: Y - e)); p.addLine(to: CGPoint(x: R - 0.9 * e, y: Y)); p.addLine(to: CGPoint(x: R + 0.9 * e, y: Y + e))
            eyes.stroke(p, with: .color(ink), style: stroke)
        case .waiting, .recovered:
            // Closed eyes: sleepy arcs down, happy arcs up.
            let (y0, dy): (CGFloat, CGFloat) = mood == .waiting ? (Y - 0.3, 1.1 * e) : (Y + 0.5, -1.4 * e)
            var p = Path()
            for x in [L, R] {
                p.move(to: CGPoint(x: x - e, y: y0))
                p.addQuadCurve(to: CGPoint(x: x + e, y: y0), control: CGPoint(x: x, y: y0 + dy))
            }
            eyes.stroke(p, with: .color(ink), style: stroke)
        case .disconnected:
            var p = Path()
            for x in [L, R] { p.addEllipse(in: CGRect(x: x - 0.95 * e, y: Y - 0.95 * e, width: 1.9 * e, height: 1.9 * e)) }
            eyes.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: sw * 0.7, lineCap: .round))
        default:
            let r: CGFloat = mono ? 1.05 : 0.82
            var p = Path()
            for x in [L, R] { p.addEllipse(in: CGRect(x: x - r, y: Y - r, width: 2 * r, height: 2 * r)) }
            eyes.fill(p, with: .color(ink))
        }

        if mood == .waiting {
            // Floating "z", 2.6 s cycle: fades in by 30 %, drifts up-right, fades out.
            let phase = animated ? t.truncatingRemainder(dividingBy: 2.6) / 2.6 : 0.3
            var z = gc
            z.opacity = phase < 0.3 ? phase / 0.3 : 1 - (phase - 0.3) / 0.7
            z.draw(Text("z").font(.system(size: 5, weight: .bold)).foregroundColor(ink),
                   at: CGPoint(x: 17.5 + 3 * phase, y: 7.5 - 5 * phase), anchor: .bottomLeading)
        }
        if mood == .low && !mono {
            var drop = Path()
            drop.move(to: CGPoint(x: 19.4, y: 6))
            drop.addQuadCurve(to: CGPoint(x: 19.4, y: 8.6), control: CGPoint(x: 20.7, y: 7.8))
            drop.addQuadCurve(to: CGPoint(x: 19.4, y: 6), control: CGPoint(x: 18.1, y: 7.8))
            gc.fill(drop, with: .color(Palette.droplet))
        }
    }
}
