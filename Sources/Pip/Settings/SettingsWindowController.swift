import AppKit
import PipCore
import SwiftUI

/// Native preferences window: toolbar tabs (General, Providers, Appearance,
/// Alerts) that resize the window to each pane.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let makeTabs: @MainActor () -> NSTabViewController

    init(prefs: Preferences, coordinator: UsageCoordinator, motion: MotionController, launchAtLogin: LaunchAtLogin, accounts: AccountManager) {
        makeTabs = {
            let tabs = NSTabViewController()
            tabs.tabStyle = .toolbar
            tabs.canPropagateSelectedChildViewControllerTitle = true
            @MainActor func add<V: View>(_ title: String, _ symbol: String, _ view: V) {
                let host = NSHostingController(rootView: view)
                host.sizingOptions = [.preferredContentSize]
                host.title = title
                let item = NSTabViewItem(viewController: host)
                item.label = title
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
                tabs.addTabViewItem(item)
            }
            add("General", "gearshape", GeneralPane(prefs: prefs, launchAtLogin: launchAtLogin))
            add("Providers", "square.stack.3d.up", ProvidersPane(prefs: prefs, coordinator: coordinator, accounts: accounts))
            add("Appearance", "paintpalette", AppearancePane(prefs: prefs, motion: motion))
            add("Alerts", "bell.badge", AlertsPane(prefs: prefs))
            return tabs
        }
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: makeTabs())
            w.styleMask = [.titled, .closable]
            w.toolbarStyle = .preference
            w.isReleasedWhenClosed = false
            w.center()
            w.setFrameAutosaveName("PipSettings")
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
