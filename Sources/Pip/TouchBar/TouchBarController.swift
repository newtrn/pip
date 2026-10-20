import AppKit
import Combine
import PipCore
import SwiftUI

/// Touch Bar support.
///
/// With public API alone, macOS shows an app's Touch Bar only while that app is
/// frontmost, so the strip appears while Pip's popover is open. When the user
/// opts in to "Keep Pip in the Control Strip", Pip uses the private Control
/// Strip API (see `ControlStrip`) to sit there permanently and expand into the
/// full strip over any app, which is what the design describes.
@MainActor
final class TouchBarController: NSObject, NSTouchBarDelegate {
    static let stripID = NSTouchBarItem.Identifier("dev.pip.Pip.touchbar.strip")
    static let trayID = NSTouchBarItem.Identifier("dev.pip.Pip.touchbar.controlstrip")

    private let coordinator: UsageCoordinator
    private let prefs: Preferences
    private let motion: MotionController
    private var trayItem: NSCustomTouchBarItem?
    private var modalBar: NSTouchBar?
    private var modalShown = false
    private var cancellables: Set<AnyCancellable> = []

    init(coordinator: UsageCoordinator, prefs: Preferences, motion: MotionController) {
        self.coordinator = coordinator
        self.prefs = prefs
        self.motion = motion
        super.init()
        prefs.$touchBarEnabled.combineLatest(prefs.$controlStrip)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.applyControlStrip() }
            .store(in: &cancellables)
        // The strip's width depends on how many providers are visible: rebuild it.
        prefs.$enabled.dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildModal() }
            .store(in: &cancellables)
    }

    /// Touch Bar MacBook Pro models (2016–2022). There is no public "has Touch
    /// Bar" API, so the hardware model identifier is matched instead.
    static let isSupported: Bool = {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buf = [UInt8](repeating: 0, count: max(1, size))
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        let model = String(decoding: buf.prefix { $0 != 0 }, as: UTF8.self)
        let touchBarModels: Set<String> = [
            "MacBookPro13,2", "MacBookPro13,3", "MacBookPro14,2", "MacBookPro14,3",
            "MacBookPro15,1", "MacBookPro15,2", "MacBookPro15,3", "MacBookPro15,4",
            "MacBookPro16,1", "MacBookPro16,2", "MacBookPro16,3", "MacBookPro16,4",
            "MacBookPro17,1", "Mac14,7",
        ]
        return touchBarModels.contains(model)
    }()

    var controlStripActive: Bool {
        Self.isSupported && prefs.touchBarEnabled && prefs.controlStrip && ControlStrip.isAvailable
    }

    /// Whether the popover should bring Pip forward to show its own Touch Bar.
    /// Not needed when Pip already lives in the Control Strip.
    var isActive: Bool { Self.isSupported && prefs.touchBarEnabled && !controlStripActive }

    func makeTouchBar(persistent: Bool = false) -> NSTouchBar {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [Self.stripID]
        bar.principalItemIdentifier = Self.stripID
        bar.customizationIdentifier = persistent ? "dev.pip.Pip.touchbar.modal" : nil
        return bar
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == Self.stripID else { return nil }
        let persistent = touchBar === modalBar
        let item = NSCustomTouchBarItem(identifier: identifier)
        let host = NSHostingView(rootView: TouchBarStrip(coordinator: coordinator, prefs: prefs, motion: motion, persistent: persistent))
        // The Touch Bar hides an item outright when it doesn't fit, which is what
        // happened next to the system close box. So the strip is flexible: it asks
        // for roomy boxes, but may shrink to the width where every name still fits.
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = false
        let n = CGFloat(max(1, prefs.visibleProviders.count)), gaps = (n - 1) * TouchBarStrip.spacing
        let ideal = host.widthAnchor.constraint(equalToConstant: n * TouchBarStrip.idealBoxWidth + gaps)
        ideal.priority = .defaultLow
        NSLayoutConstraint.activate([
            host.widthAnchor.constraint(greaterThanOrEqualToConstant: n * TouchBarStrip.minBoxWidth + gaps),
            ideal,
            host.heightAnchor.constraint(equalToConstant: 30),
        ])
        host.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        item.view = host
        item.customizationLabel = "Pip usage"
        return item
    }

    // MARK: Control Strip

    private func applyControlStrip() {
        if controlStripActive {
            guard trayItem == nil else { return }
            let item = NSCustomTouchBarItem(identifier: Self.trayID)
            let button = NSButton(title: "", target: self, action: #selector(toggleModal))
            button.bezelStyle = .rounded
            button.isBordered = false
            let host = PassthroughHostingView(rootView: ControlStripButton(coordinator: coordinator, prefs: prefs, motion: motion))
            host.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                host.topAnchor.constraint(equalTo: button.topAnchor),
                host.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            ])
            item.view = button
            item.customizationLabel = "Pip"
            trayItem = item
            ControlStrip.setTrayItem(item, visible: true)
        } else {
            removeControlStrip()
        }
    }

    func removeControlStrip() {
        if let bar = modalBar, modalShown { ControlStrip.dismissModal(bar) }
        modalShown = false
        modalBar = nil
        if let item = trayItem { ControlStrip.setTrayItem(item, visible: false) }
        trayItem = nil
    }

    private func rebuildModal() {
        guard let bar = modalBar else { return }
        let wasShown = modalShown
        if wasShown { ControlStrip.dismissModal(bar) }
        modalShown = false
        modalBar = nil
        if wasShown { toggleModal() }
    }

    /// Development aid (`Pip --expand-strip`): expands the strip at launch so it
    /// can be captured with `screencapture -b`.
    func expandControlStrip() {
        if controlStripActive && !modalShown { toggleModal() }
    }

    /// Tapping Pip in the Control Strip expands the full strip; tapping again collapses it.
    @objc private func toggleModal() {
        if modalShown, let bar = modalBar {
            ControlStrip.dismissModal(bar)
            modalShown = false
            return
        }
        let bar = modalBar ?? {
            let b = NSTouchBar()
            modalBar = b
            b.delegate = self
            b.defaultItemIdentifiers = [Self.stripID]
            b.principalItemIdentifier = Self.stripID
            return b
        }()
        ControlStrip.presentModal(bar, trayIdentifier: Self.trayID)
        modalShown = true
    }
}

/// Pip and the active provider's number, sized for a Control Strip slot.
struct ControlStripButton: View {
    @ObservedObject var coordinator: UsageCoordinator
    @ObservedObject var prefs: Preferences
    @ObservedObject var motion: MotionController
    private let fg = Color(hex: 0xF2F2F2)

    var body: some View {
        let s = coordinator.state(prefs.active), p = Palette(dark: true)
        let rem = s.remaining
        HStack(spacing: 0) {
            SlimeView(mood: s.mood, level: Double(rem ?? 100) / 100, size: 18,
                      style: .mono(ink: fg, tint: (rem ?? 100) <= 25 ? p.level(rem ?? 0, hue: s.hue) : Color(oklch: 0.74, 0.14, s.hue)),
                      fps: motion.menuBarFPS, paused: !motion.menuBarAwake && coordinator.recovering.isEmpty)
        }
        .padding(.horizontal, 8)
        .accessibilityLabel("Pip, \(s.descriptor.name) \(UsagePresenter(showUsed: prefs.showUsed, now: coordinator.now).compactValue(for: s.snapshot, status: s.status))")
        .frame(height: 30)
        .environment(\.colorScheme, .dark)
    }
}

/// The Touch Bar strip: one usage box per visible provider, each with its own
/// small Pip. Always drawn dark, like the Touch Bar.
struct TouchBarStrip: View {
    @ObservedObject var coordinator: UsageCoordinator
    @ObservedObject var prefs: Preferences
    @ObservedObject var motion: MotionController
    /// Shown over other apps from the Control Strip: animate in short bursts
    /// like the menu bar, since it can stay up indefinitely.
    var persistent = false

    static let spacing: CGFloat = 5
    /// Room for the longest tab name ("Anthropic"), its dot and a 22 pt Pip.
    static let minBoxWidth: CGFloat = 124
    static let idealBoxWidth: CGFloat = 190

    private let fg = Color(hex: 0xF2F2F2)
    private var fps: Double? { persistent ? motion.menuBarFPS : motion.popoverFPS }
    private var paused: Bool { persistent && !motion.menuBarAwake && coordinator.recovering.isEmpty }
    private var presenter: UsagePresenter { UsagePresenter(showUsed: prefs.showUsed, now: coordinator.now) }
    private var palette: Palette { Palette(dark: true) }
    private var font: Font { prefs.style == .type ? PipFont.mono(12) : .system(size: 12) }

    var body: some View {
        // Just the per-provider usage boxes: no lead mascot, no status line.
        HStack(spacing: Self.spacing) {
            ForEach(prefs.visibleProviders) { q in providerButton(q) }
        }
        .frame(height: 30)
        .environment(\.colorScheme, .dark)
    }

    /// The name, drawn by AppKit into an image. On the real Touch Bar a SwiftUI
    /// Text came out as "Cod…" however much room it had (offscreen renders were
    /// fine), so the Touch Bar gets no text to lay out at all.
    private func nameLabel(_ name: String) -> some View {
        let nsFont = prefs.style == .type ? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular) : NSFont.systemFont(ofSize: 12)
        let attributed = NSAttributedString(string: name, attributes: [.font: nsFont, .foregroundColor: NSColor(fg)])
        return Image(nsImage: Self.textImage(attributed)).accessibilityHidden(true)
    }

    /// Not main-actor isolated: AppKit may run the drawing handler on another thread.
    nonisolated private static func textImage(_ attributed: NSAttributedString) -> NSImage {
        let size = attributed.size()
        return NSImage(size: NSSize(width: ceil(size.width), height: ceil(size.height)), flipped: false) { _ in
            attributed.draw(at: .zero)
            return true
        }
    }

    /// One provider's box: dot, full name and its usage as a small Pip (or
    /// segments in the Energy style). No number — the shape and level carry it.
    private func providerButton(_ q: ProviderID) -> some View {
        let s = coordinator.state(q)
        let rem = s.remaining
        let fr = s.isUnavailable ? 0 : Double(rem.map { prefs.showUsed ? 100 - $0 : $0 } ?? 100) / 100
        let color = palette.value(remaining: rem, hue: s.hue, showUsed: prefs.showUsed)
        let dot = Circle().fill(s.isUnavailable ? Color(hex: 0x666666) : rem.map { palette.level($0, hue: s.hue) } ?? palette.provider(s.hue))
            .frame(width: 6, height: 6)
        let name = prefs.style == .type ? s.descriptor.tabName.lowercased() : s.descriptor.tabName
        return Button { prefs.active = q } label: {
            // The name is never truncated: when a box gets squeezed (other
            // apps' items, the Control Strip) Pip goes first, then the long name.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 7) {
                    dot
                    nameLabel(name)
                    Spacer(minLength: 4)
                    if prefs.style == .energy {
                        Segments(count: 8, fraction: fr, color: color, off: Color.white.opacity(0.14), height: 10, radius: 1.5, gap: 1.5, stagger: 0.04)
                            .frame(width: 64)
                    } else if prefs.style != .type {
                        SlimeView(mood: s.mood, level: fr, size: 22,
                                  style: .color(mood: s.mood, remaining: rem ?? 100, hue: s.hue, dark: true), fps: fps, paused: paused)
                    }
                }
                HStack(spacing: 7) {
                    dot
                    nameLabel(name)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 5) {
                    dot
                    Text(s.descriptor.short).font(font).lineLimit(1).fixedSize()
                    Spacer(minLength: 0)
                }
            }
            .foregroundColor(fg)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: q == prefs.active ? 0x3A3A3C : 0x1C1C1E)))
            .accessibilityLabel("\(s.descriptor.name), \(presenter.compactValue(for: s.snapshot, status: s.status))")
        }
        .buttonStyle(.plain)
    }
}
