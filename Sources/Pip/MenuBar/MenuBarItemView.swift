import PipCore
import SwiftUI

/// The status item's content (`menuItem()` in the prototype). Monochrome by
/// default so it sits with the system icons; tinted only when it needs attention.
struct MenuBarItemView: View {
    @ObservedObject var coordinator: UsageCoordinator
    @ObservedObject var prefs: Preferences
    @ObservedObject var motion: MotionController
    /// Reports the rendered width so the status item can size itself.
    var onWidth: (CGFloat) -> Void = { _ in }

    @Environment(\.colorScheme) private var scheme

    private var presenter: UsagePresenter { UsagePresenter(showUsed: prefs.showUsed, now: coordinator.now) }
    private var visible: [ProviderID] { prefs.visibleProviders }
    private let text = Font.system(size: 12.5, weight: .medium).monospacedDigit()
    private let mono = PipFont.mono(11.5, weight: .medium)

    var body: some View {
        content
            .foregroundColor(.primary)
            .padding(.horizontal, 6)
            .frame(height: 22)
            .fixedSize()
            .background(GeometryReader { g in Color.clear.preference(key: WidthKey.self, value: g.size.width) })
            .onPreferenceChange(WidthKey.self, perform: onWidth)
    }

    @ViewBuilder private var content: some View {
        let style = prefs.style, layout = prefs.menuBarLayout
        switch style {
        case .energy: energy(layout)
        case .type: typographic(layout)
        case .companion, .hybrid:
            if !prefs.mascotOn {
                Text(pct(prefs.active)).font(text).tracking(-0.125)
            } else {
                companion(layout)
            }
        }
    }

    // MARK: Companion / Hybrid

    @ViewBuilder private func companion(_ layout: MenuBarLayout) -> some View {
        let active = prefs.active
        switch layout {
        case .mascot: pip(active, size: 17)
        case .ultra: pip(active, size: 15)
        case .multi:
            HStack(spacing: 5) {
                pip(active, size: 17)
                HStack(spacing: 6) {
                    ForEach(visible) { q in
                        HStack(spacing: 2) {
                            Text(ProviderDescriptor.of(q).short).font(.system(size: 10.5, weight: .medium)).opacity(0.5)
                            Text(pct(q, symbol: false)).font(text)
                        }
                        .foregroundColor(tint(q) ?? .primary)
                    }
                }
            }
        case .animated:
            rotating { q in
                HStack(spacing: 5) {
                    pip(q, size: 17)
                    HStack(spacing: 3) {
                        Text(ProviderDescriptor.of(q).short).font(.system(size: 10.5, weight: .medium)).opacity(0.5)
                        Text(pct(q)).font(text)
                    }
                    .transition(.tickIn)
                }
            }
        case .mascotPct:
            HStack(spacing: 5) {
                pip(active, size: 17)
                Text(pct(active)).font(text).tracking(-0.125).foregroundColor(tint(active) ?? .primary)
            }
        }
    }

    private func pip(_ id: ProviderID, size: CGFloat) -> some View {
        let s = coordinator.state(id)
        // The Companion style keeps the menu bar Pip full; only Hybrid shows the level.
        let level = prefs.style == .companion && prefs.menuBarLayout != .animated ? 1 : Double(s.remaining ?? 100) / 100
        // Move continuously while celebrating a refill; otherwise only in the wake-up bursts.
        let paused = !motion.menuBarAwake && coordinator.recovering.isEmpty
        return SlimeView(mood: s.mood, level: level, size: size,
                         style: .mono(ink: .primary, tint: tint(id)), fps: motion.menuBarFPS, paused: paused)
    }

    // MARK: Energy

    @ViewBuilder private func energy(_ layout: MenuBarLayout) -> some View {
        switch layout {
        case .multi:
            VStack(spacing: 1.5) {
                ForEach(visible) { q in Battery(n: 6, w: 3.4, h: 3, r: 1, gap: 1, fraction: fraction(q), color: barColor(q)) }
            }
        case .ultra:
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(visible) { q in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 1.5).fill(Color.primary.opacity(0.2))
                        RoundedRectangle(cornerRadius: 1.5).fill(barColor(q)).frame(height: 13 * fraction(q))
                    }
                    .frame(width: 3.5, height: 13)
                    .animation(.easeOut(duration: 1), value: fraction(q))
                }
            }
        case .mascot:
            Battery(n: 5, w: 4, h: 10, r: 1.5, gap: 1.5, fraction: fraction(prefs.active), color: barColor(prefs.active))
        case .animated:
            rotating { q in
                HStack(spacing: 5) {
                    Text(ProviderDescriptor.of(q).short).font(mono).opacity(0.6)
                    Battery(n: 5, w: 4, h: 10, r: 1.5, gap: 1.5, fraction: fraction(q), color: barColor(q))
                    Text(pct(q, symbol: false)).font(text)
                }
                .transition(.tickIn)
            }
        case .mascotPct:
            HStack(spacing: 5) {
                Battery(n: 5, w: 4, h: 10, r: 1.5, gap: 1.5, fraction: fraction(prefs.active), color: barColor(prefs.active))
                Text(pct(prefs.active, symbol: false)).font(text)
            }
        }
    }

    // MARK: Typographic

    @ViewBuilder private func typographic(_ layout: MenuBarLayout) -> some View {
        let active = prefs.active
        switch layout {
        case .mascot, .ultra:
            Text(pct(active, symbol: layout != .ultra)).font(PipFont.mono(11.5, weight: .semibold)).foregroundColor(tint(active) ?? .primary)
        case .multi:
            HStack(spacing: 7) {
                ForEach(visible) { q in
                    (Text(ProviderDescriptor.of(q).short).foregroundColor(.primary.opacity(0.5)) + Text(" " + pct(q, symbol: false)))
                        .foregroundColor(tint(q) ?? .primary)
                }
            }
            .font(mono)
        case .animated, .mascotPct:
            let one = { (q: ProviderID) in
                Text(ProviderDescriptor.of(q).tabName + " ")
                    + Text(pct(q)).fontWeight(.semibold).foregroundColor(tint(q) ?? .primary)
                    + Text(prefs.showUsed ? " used" : " left")
            }
            if layout == .animated {
                rotating { q in one(q).font(mono).transition(.tickIn) }
            } else {
                one(active).font(mono)
            }
        }
    }

    // MARK: Helpers

    /// Cycles through visible providers every 3 s (the prototype's `cyc`).
    private func rotating<V: View>(@ViewBuilder _ make: @escaping (ProviderID) -> V) -> some View {
        TimelineView(.periodic(from: .now, by: 3)) { ctx in
            let list = visible
            let i = Int(ctx.date.timeIntervalSinceReferenceDate / 3) % max(1, list.count)
            let q = list.isEmpty ? prefs.active : list[i]
            ZStack { make(q).id(q) }
                .animation(motion.animates ? .easeOut(duration: 0.4) : nil, value: q)
        }
    }

    private func pct(_ id: ProviderID, symbol: Bool = true) -> String {
        let s = coordinator.state(id)
        let value = presenter.compactValue(for: s.snapshot, status: s.status)
        return symbol ? value : value.replacingOccurrences(of: "%", with: "")
    }

    private func fraction(_ id: ProviderID) -> Double {
        guard let rem = coordinator.state(id).remaining else { return 0 }
        return Double(prefs.showUsed ? 100 - rem : rem) / 100
    }

    /// Icon tint rule from Settings → Icon color.
    private func tint(_ id: ProviderID) -> Color? {
        let s = coordinator.state(id), p = Palette(dark: scheme == .dark)
        switch prefs.iconColor {
        case .always: return p.provider(s.hue)
        case .attention:
            if let rem = s.remaining, rem <= 25, s.isLive { return p.level(rem, hue: s.hue) }
            return nil
        case .never: return nil
        }
    }

    private func barColor(_ id: ProviderID) -> Color { tint(id) ?? .primary }
}

/// Segmented battery used by the Energy style.
struct Battery: View {
    var n: Int, w: CGFloat, h: CGFloat, r: CGFloat, gap: CGFloat
    var fraction: Double
    var color: Color

    var body: some View {
        let on = Int((fraction * Double(n)).rounded())
        HStack(spacing: gap) {
            ForEach(0..<n, id: \.self) { i in
                RoundedRectangle(cornerRadius: r)
                    .fill(i < on ? color : Color.primary.opacity(0.2))
                    .frame(width: w, height: h)
                    .animation(.easeOut(duration: 0.4).delay(Double(i) * 0.04), value: on)
            }
        }
    }
}

private struct WidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

extension AnyTransition {
    /// `tickIn`: fade up 5 pt.
    static var tickIn: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .offset(y: 5)), removal: .opacity)
    }
}
