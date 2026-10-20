import AppKit
import PipCore
import SwiftUI

/// SwiftUI content inside the status bar button. It must not swallow clicks,
/// so the button keeps its native highlight and action handling.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Owns the NSStatusItem and keeps its width in step with the SwiftUI content.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover: PopoverController

    init(coordinator: UsageCoordinator, prefs: Preferences, motion: MotionController, popover: PopoverController) {
        self.popover = popover
        super.init()
        guard let button = item.button else { return }
        let view = MenuBarItemView(coordinator: coordinator, prefs: prefs, motion: motion) { [weak self] width in
            // Setting length relayouts the status bar, so only do it on real changes.
            guard let item = self?.item, item.length != ceil(width) else { return }
            item.length = ceil(width)
        }
        let host = PassthroughHostingView(rootView: view)
        host.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            host.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityTitle("Pip usage")
        item.autosaveName = "PipStatusItem"
    }

    @objc private func clicked() {
        guard let button = item.button else { return }
        popover.toggle(from: button)
    }

    var button: NSStatusBarButton? { item.button }
}
