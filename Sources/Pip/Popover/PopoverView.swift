import PipCore
import SwiftUI

/// Actions the popover asks its host to perform.
struct PopoverActions {
    var openSettings: () -> Void = {}
    var sizeChanged: (CGSize) -> Void = { _ in }
}

/// The detailed popover (`pop` in the prototype): header, provider tabs,
/// status banner, mascot tubes, metric rows and footer.
struct PopoverView: View {
    @ObservedObject var coordinator: UsageCoordinator
    @ObservedObject var prefs: Preferences
    @ObservedObject var motion: MotionController
    var actions = PopoverActions()
    /// Solid background instead of the blur, for offscreen snapshots.
    var opaqueBackground = false

    @Environment(\.colorScheme) private var scheme
    @State private var appeared = false

    private var dark: Bool { scheme == .dark }
    private var pt: PopoverTokens { .of(dark: dark) }
    private var palette: Palette { Palette(dark: dark) }
    private var presenter: UsagePresenter { UsagePresenter(showUsed: prefs.showUsed, now: coordinator.now) }
    private var compact: Bool { prefs.compact }

    var body: some View {
        let s = coordinator.state(prefs.active)
        VStack(alignment: .leading, spacing: 0) {
            header(s)
            tabs
            banner(s)
            metrics(s)
            footer(s)
        }
        .padding(compact ? EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12) : EdgeInsets(top: 14, leading: 14, bottom: 10, trailing: 14))
        .frame(width: compact ? 296 : 340)
        .foregroundColor(pt.fg)
        .font(.system(size: 13))
        .background(chrome)
        // `inset 0 .5px 0 rim`: a hairline highlight along the top edge.
        .overlay(pt.rim.frame(height: 0.5).allowsHitTesting(false), alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(pt.edge, lineWidth: 0.5))
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { g in Color.clear.preference(key: SizeKey.self, value: g.size) })
        .onPreferenceChange(SizeKey.self, perform: actions.sizeChanged)
        // popIn: .22 s, cubic-bezier(.2,.9,.3,1)
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.98, anchor: .top)
        .offset(y: appeared ? 0 : -6)
        .onAppear {
            guard !opaqueBackground else { appeared = true; return }
            withAnimation(motion.animates ? .timingCurve(0.2, 0.9, 0.3, 1, duration: 0.22) : nil) { appeared = true }
        }
    }

    @ViewBuilder private var chrome: some View {
        if opaqueBackground {
            (dark ? Color(rgba: 40, 40, 43) : Color(rgba: 251, 250, 248))
        } else {
            ZStack { VisualEffectBlur(); pt.bg }
        }
    }

    // MARK: Header

    @ViewBuilder private func header(_ s: ProviderState) -> some View {
        let snap = s.snapshot
        let hd = snap.map { presenter.header(for: $0, providerName: s.descriptor.name, status: s.status, recovering: s.recovering) }
        let color = s.isUnavailable ? pt.sub : palette.value(remaining: hd?.remaining, hue: s.hue, showUsed: prefs.showUsed)
        let big = hd?.big ?? "—", unit = hd?.unit ?? "", word = hd?.word ?? "", resetLine = hd?.resetLine ?? "—"
        let line = s.line(presenter: presenter)
        let plan = snap?.plan ?? ""

        switch prefs.style {
        case .companion:
            HStack(spacing: 14) {
                bigPip(s, size: 64)
                VStack(alignment: .leading, spacing: 6) {
                    Text(line).font(.system(size: 13)).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 9).padding(.horizontal, 12)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(pt.card))
                    Text("\(s.descriptor.name) · \(plan)").font(.system(size: 11.5)).foregroundColor(pt.sub).padding(.leading, 4)
                }
            }
            .padding(EdgeInsets(top: 4, leading: 2, bottom: 14, trailing: 2))
        case .energy:
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    Text(s.descriptor.name).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("STAMINA · \(hd?.windowShort ?? "—")").font(PipFont.mono(10.5)).tracking(1.26).foregroundColor(pt.sub)
                }
                Segments(count: 20, fraction: hd?.fraction ?? 0, color: color, off: pt.segOff, height: 16, radius: 3, gap: 2.5, stagger: 0.03)
                    .padding(3)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(pt.card))
                HStack(alignment: .firstTextBaseline) {
                    (Text(big + unit).font(.system(size: 15, weight: .bold).monospacedDigit()) + Text(" " + word)).font(.system(size: 12))
                    Spacer()
                    Text(resetLine).font(.system(size: 12)).foregroundColor(pt.sub)
                }
            }
            .padding(EdgeInsets(top: 2, leading: 2, bottom: 14, trailing: 2))
        case .type:
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(big).font(PipFont.serif(84)).tracking(-2.5).foregroundColor(color)
                    Text(unit).font(PipFont.serif(40))
                }
                // line-height .9 in the design: pull the next line up under the numeral.
                .padding(.bottom, -8)
                Text(hd?.sentence ?? "").font(PipFont.serif(21)).lineSpacing(0).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                Text("— " + line).font(PipFont.mono(11)).foregroundColor(pt.sub).padding(.top, 8).fixedSize(horizontal: false, vertical: true)
            }
            .padding(EdgeInsets(top: 0, leading: 2, bottom: 14, trailing: 2))
        case .hybrid:
            HStack(spacing: 14) {
                bigPip(s, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(line).font(.system(size: 12.5, weight: .medium)).lineSpacing(1).fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(big + unit).font(.system(size: 30, weight: .semibold).monospacedDigit()).tracking(-0.9).foregroundColor(color)
                        Text(word.isEmpty ? resetLine : "\(word) · \(resetLine)").font(.system(size: 12)).foregroundColor(pt.sub)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: 2, leading: 2, bottom: 14, trailing: 2))
        }
    }

    private func bigPip(_ s: ProviderState, size: CGFloat) -> some View {
        let rem = s.isUnavailable ? 0 : s.remaining ?? 100
        return SlimeView(mood: s.mood, level: Double(rem) / 100, size: size,
                         style: .color(mood: s.mood, remaining: rem, hue: s.hue, dark: dark), fps: motion.popoverFPS)
    }

    // MARK: Tabs

    private var tabs: some View {
        HStack(spacing: 3) {
            ForEach(prefs.visibleProviders) { q in
                let s = coordinator.state(q), on = q == prefs.active
                Button {
                    prefs.active = q
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(s.status.isOffline ? pt.sub : s.remaining.map { palette.level($0, hue: s.hue) } ?? palette.provider(s.hue))
                            .frame(width: 7, height: 7)
                        Text(s.descriptor.tabName).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text(presenter.compactValue(for: s.snapshot, status: s.status))
                            .font(.system(size: 11).monospacedDigit()).foregroundColor(pt.sub).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? pt.tabOn : .clear)
                        .shadow(color: .black.opacity(on ? 0.12 : 0), radius: 1, y: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(s.descriptor.name), \(presenter.compactValue(for: s.snapshot, status: s.status))")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(pt.card))
    }

    // MARK: Banner

    @ViewBuilder private func banner(_ s: ProviderState) -> some View {
        let name = s.descriptor.name
        let b: (String, Color, Color)? = {
            switch s.mood {
            case .disconnected:
                let reason: String = { if case .offline(let r) = s.status { return r }; return "retrying in a minute" }()
                return ("Couldn't reach \(name) · \(reason).", Palette.bad.opacity(0.14), Palette.bad)
            case .stale: return ("Showing data from \(s.staleMinutes) min ago — the last refresh failed.", Palette.warn.opacity(0.16), Color(oklch: 0.72, 0.15, 70))
            case .loading: return ("Connecting to \(name)…", pt.card, pt.sub)
            case .recovered: return ("Window reset. Back to a full tank.", Color(oklch: 0.72, 0.14, 150, opacity: 0.16), Palette.good)
            default: return nil
            }
        }()
        if let (text, bg, dot) = b {
            HStack(spacing: 8) {
                Circle().fill(dot).frame(width: 6, height: 6)
                Text(text).font(.system(size: 11.5)).lineSpacing(1).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8).padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(bg))
            .padding(.top, 10)
            .transition(.opacity)
        }
    }

    // MARK: Metrics

    @ViewBuilder private func metrics(_ s: ProviderState) -> some View {
        if let snap = s.snapshot {
            let rows = presenter.rows(for: snap, status: s.status, recovering: s.recovering, limit: compact ? 2 : nil)
            let usesTubes = prefs.style.showsMascot
            let tubes = usesTubes ? rows.filter { $0.fraction != nil } : []
            let plain = rows.filter { !tubes.contains($0) }
            if !tubes.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(tubes.enumerated()), id: \.element.id) { i, r in tube(r, index: i, hue: s.hue) }
                }
                // Cards stretch to the tallest one so the row reads as a set.
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            }
            VStack(spacing: 0) {
                ForEach(Array(plain.enumerated()), id: \.element.id) { i, r in
                    row(r, showSub: !(compact && i + tubes.count > 0), hue: s.hue)
                }
            }
            .padding(.top, 6)
        }
    }

    private func tube(_ r: UsagePresenter.Row, index: Int, hue: Double) -> some View {
        let rem = r.remaining ?? 100
        return VStack(spacing: 7) {
            SlimeView(mood: r.mood, level: r.fraction ?? 0, size: compact ? 44 : 64,
                      style: .color(mood: r.mood, remaining: rem, hue: hue, dark: dark), fps: motion.popoverFPS)
                .frame(height: compact ? 48 : 68, alignment: .bottom)
            VStack(spacing: 1) {
                Text(r.big).font(.system(size: 17, weight: .semibold).monospacedDigit()).tracking(-0.34).shimmer(r.shimmer && motion.animates)
                Text(r.word).font(.system(size: 10.5)).foregroundColor(pt.sub)
            }
            Text(r.label).font(.system(size: 11)).multilineTextAlignment(.center).lineSpacing(1).fixedSize(horizontal: false, vertical: true)
            if let sub = r.sub, !(compact && index > 0) {
                Text(sub).font(.system(size: 10)).foregroundColor(pt.sub).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(EdgeInsets(top: 12, leading: 6, bottom: 10, trailing: 6))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(pt.card))
        .opacity(r.dimmed ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }

    private func row(_ r: UsagePresenter.Row, showSub: Bool, hue: Double) -> some View {
        let typeStyle = prefs.style == .type
        let color = palette.value(remaining: r.remaining, hue: hue, showUsed: prefs.showUsed)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(r.label).font(.system(size: 12)).foregroundColor(pt.sub)
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(r.big)
                        .font(typeStyle ? PipFont.serif(22) : .system(size: compact ? 13 : 14, weight: .semibold).monospacedDigit())
                        .shimmer(r.shimmer && motion.animates)
                    Text(r.word).font(.system(size: 11.5)).foregroundColor(pt.sub)
                }
                .lineLimit(1)
            }
            if prefs.style == .energy, let f = r.fraction {
                Segments(count: 10, fraction: f, color: color, off: pt.segOff, height: 6, radius: 2, gap: 2, stagger: 0.035)
            }
            if showSub, let sub = r.sub {
                Text(sub).font(.system(size: 11)).foregroundColor(pt.sub)
            }
        }
        .padding(.vertical, compact ? 7 : 10).padding(.horizontal, 2)
        .overlay(Rectangle().fill(pt.hair).frame(height: 0.5), alignment: .top)
        .opacity(r.dimmed ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }

    // MARK: Footer

    private func footer(_ s: ProviderState) -> some View {
        let updated: String = {
            switch s.status {
            case .stale: return "Updated \(s.staleMinutes) min ago"
            case .loading: return "Updating…"
            case .offline, .paused: return "Offline"
            case .live:
                guard let at = s.snapshot?.fetchedAt else { return "Updated just now" }
                let mins = Int(coordinator.now.timeIntervalSince(at) / 60)
                return mins < 1 ? "Updated just now" : "Updated \(mins) min ago"
            }
        }()
        return HStack {
            Text(updated + (s.snapshot?.isDemo == true ? " · Demo data" : ""))
            Spacer()
            HStack(spacing: 4) {
                FooterButton(title: "Refresh", fg: pt.fg) { coordinator.refresh(prefs.active) }
                FooterButton(title: "Settings…", fg: pt.fg, action: actions.openSettings)
            }
        }
        .font(.system(size: 11.5))
        .foregroundColor(pt.sub)
        .padding(.top, 9)
        .overlay(Rectangle().fill(pt.hair).frame(height: 0.5), alignment: .top)
        .padding(.top, 2)
    }
}

/// Row of segments that fill left to right with a stagger (Energy style).
struct Segments: View {
    var count: Int
    var fraction: Double
    var color: Color
    var off: Color
    var height: CGFloat
    var radius: CGFloat
    var gap: CGFloat
    var stagger: Double

    var body: some View {
        let on = Int((fraction * Double(count)).rounded())
        HStack(spacing: gap) {
            ForEach(0..<count, id: \.self) { k in
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(k < on ? color : off)
                    .frame(height: height)
                    .animation(.easeInOut(duration: 0.35).delay(Double(k) * stagger), value: on)
            }
        }
    }
}

private struct FooterButton: View {
    var title: String
    var fg: Color
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title).foregroundColor(fg)
                .padding(.vertical, 4).padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(hover ? 0.16 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct ShimmerModifier: ViewModifier {
    var active: Bool
    @State private var dim = false
    func body(content: Content) -> some View {
        content
            .opacity(active ? (dim ? 0.35 : 0.85) : 1)
            .onAppear(perform: update)
            .onChange(of: active) { _ in update() }
    }

    private func update() {
        if active {
            withAnimation(.easeInOut(duration: 0.6).repeatForever()) { dim = true }
        } else {
            withAnimation(nil) { dim = false }
        }
    }
}

extension View {
    /// Loading pulse (`shimmer 1.2s infinite`).
    func shimmer(_ active: Bool) -> some View { modifier(ShimmerModifier(active: active)) }
}

extension ConnectionStatus {
    var isOffline: Bool { if case .offline = self { return true }; return false }
}

private struct SizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// Behind-window blur for the popover background.
struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
