import AppKit
import Combine
import PipCore

/// Wires the app together: data (coordinator), settings, menu bar, popover,
/// Touch Bar, settings window and notifications.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var prefs: Preferences!
    private var coordinator: UsageCoordinator!
    private var motion: MotionController!
    private var statusItem: StatusItemController!
    private var popover: PopoverController!
    private var settings: SettingsWindowController!
    private var notifications: NotificationService!
    private var touchBar: TouchBarController!
    private var accounts: AccountManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        prefs = Preferences()
        motion = MotionController(preferences: prefs)
        // Real data where an API key is connected; demo data everywhere else.
        accounts = AccountManager()
        coordinator = UsageCoordinator(providers: accounts.makeProviders())
        notifications = NotificationService(prefs: prefs)
        touchBar = TouchBarController(coordinator: coordinator, prefs: prefs, motion: motion)
        settings = SettingsWindowController(prefs: prefs, coordinator: coordinator, motion: motion, launchAtLogin: LaunchAtLogin(), accounts: accounts)
        popover = PopoverController(coordinator: coordinator, prefs: prefs, motion: motion, touchBar: touchBar) { [weak self] in
            self?.popover.close()
            self?.settings.show()
        }
        popover.wantsTouchBar = { [weak self] in self?.touchBar.isActive ?? false }
        statusItem = StatusItemController(coordinator: coordinator, prefs: prefs, motion: motion, popover: popover)

        coordinator.onEvent = { [weak self] event in
            guard let self else { return }
            self.notifications.handle(event, coordinator: self.coordinator)
        }
        notifications.requestAuthorizationIfNeeded()
        coordinator.start()
        if CommandLine.arguments.contains("--expand-strip") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.touchBar.expandControlStrip() }
        }
        // Timers don't fire during sleep: catch up as soon as the Mac wakes.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.coordinator.refreshAll() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
        // Leave no orphaned item in the Control Strip.
        touchBar?.removeControlStrip()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Launching Pip again from Finder opens Settings: there is no Dock icon.
        settings.show()
        return false
    }
}
