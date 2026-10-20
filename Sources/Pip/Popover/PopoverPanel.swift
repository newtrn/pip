import AppKit
import PipCore
import SwiftUI

/// Borderless panel that hosts the popover. NSPopover always draws an arrow
/// and its own chrome; the design is an arrowless 13 pt rounded card hanging
/// just below the menu bar, which a panel reproduces exactly.
final class PopoverPanel: NSPanel {
    var touchBarFactory: (() -> NSTouchBar?)?
    var onEscape: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isMovable = false
        hidesOnDeactivate = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) { onEscape?() }

    override func makeTouchBar() -> NSTouchBar? { touchBarFactory?() }
}

/// Shows and hides the popover under the status item and closes it on outside clicks.
@MainActor
final class PopoverController {
    private let panel = PopoverPanel()
    private let hosting: NSHostingView<AnyView>
    private var makeRoot: () -> AnyView = { AnyView(EmptyView()) }
    private var monitor: Any?
    private let coordinator: UsageCoordinator
    private weak var anchor: NSStatusBarButton?
    private var activatedForTouchBar = false
    var onVisibilityChange: ((Bool) -> Void)?
    var wantsTouchBar: () -> Bool = { false }

    var isShown: Bool { panel.isVisible }

    init(coordinator: UsageCoordinator, prefs: Preferences, motion: MotionController,
         touchBar: TouchBarController, openSettings: @escaping () -> Void) {
        self.coordinator = coordinator
        hosting = NSHostingView(rootView: AnyView(EmptyView()))
        let actions = PopoverActions(
            openSettings: openSettings,
            sizeChanged: { [weak panel = panel] _ in
                // Re-measure so the panel grows downward from a fixed top edge.
                guard let panel, let view = panel.contentView else { return }
                let size = view.fittingSize
                guard size.width > 0, size != panel.frame.size else { return }
                let top = panel.frame.maxY
                panel.setFrame(NSRect(x: panel.frame.minX, y: top - size.height, width: size.width, height: size.height), display: true)
                panel.invalidateShadow()
            })
        makeRoot = { AnyView(PopoverView(coordinator: coordinator, prefs: prefs, motion: motion, actions: actions)) }
        panel.contentView = hosting
        panel.onEscape = { [weak self] in self?.close() }
        panel.touchBarFactory = { [weak self] in
            guard let self, self.wantsTouchBar() else { return nil }
            return touchBar.makeTouchBar()
        }
    }

    func toggle(from button: NSStatusBarButton) {
        isShown ? close() : show(from: button)
    }

    func show(from button: NSStatusBarButton) {
        guard let window = button.window else { return }
        anchor = button
        // Opening Pip is a good moment to catch up (each provider's minimum interval still applies).
        coordinator.refreshAll()
        // A fresh identity replays the popIn animation.
        hosting.rootView = AnyView(makeRoot().id(UUID()))
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let item = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = window.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? item
        // Design: the card hangs 4 pt below the menu bar, its right edge 96 pt past the item.
        var x = item.maxX + 96 - size.width
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        let top = item.minY - 4
        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)

        if wantsTouchBar() {
            // The Touch Bar only shows content for the frontmost app.
            NSApp.activate(ignoringOtherApps: true)
            activatedForTouchBar = true
        }
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        button.highlight(true)
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in self?.close() }
        }
        onVisibilityChange?(true)
    }

    func close() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        // An ordered-out window still runs its TimelineViews; drop the content entirely.
        hosting.rootView = AnyView(EmptyView())
        panel.touchBar = nil
        anchor?.highlight(false)
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if activatedForTouchBar {
            activatedForTouchBar = false
            // Hand focus back to the app the user was in.
            NSApp.hide(nil)
        }
        onVisibilityChange?(false)
    }
}
