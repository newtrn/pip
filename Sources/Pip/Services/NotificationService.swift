import Foundation
import PipCore
import UserNotifications

/// Turns coordinator events into user notifications, filtered by Settings → Alerts.
@MainActor
final class NotificationService {
    private let prefs: Preferences
    /// UNUserNotificationCenter crashes in a process without a bundle identifier
    /// (e.g. a bare binary run from the terminal), so notifications need the .app.
    private let available = Bundle.main.bundleIdentifier != nil

    init(prefs: Preferences) {
        self.prefs = prefs
    }

    func requestAuthorizationIfNeeded() {
        guard available, prefs.notifyLow || prefs.notifyReset || prefs.notifyDisconnect else { return }
        // The async form: a completion closure written here would be main-actor
        // isolated, and the system calls it on a background queue, which traps.
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    }

    func handle(_ event: UsageEvent, coordinator: UsageCoordinator) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        switch event {
        case .runningLow(let id, let remaining, _):
            guard prefs.notifyLow, prefs.isEnabled(id) else { return }
            let name = ProviderDescriptor.of(id).name
            let state = coordinator.state(id)
            let at = state.snapshot?.primaryQuota.map { UsagePresenter(showUsed: false, now: Date()).resetAt($0) } ?? "the next reset"
            content.title = "\(name) is running low"
            content.body = "Running on fumes. \(remaining)% left until \(at)."
        case .windowReset(let id):
            guard prefs.notifyReset, prefs.isEnabled(id) else { return }
            content.title = "\(ProviderDescriptor.of(id).name) refilled"
            content.body = "Refilled! Fresh window, full tank."
        case .connectionLost(let id):
            guard prefs.notifyDisconnect, prefs.isEnabled(id) else { return }
            content.title = "Can't reach \(ProviderDescriptor.of(id).name)"
            content.body = "Three refreshes in a row failed. Pip is hiding the numbers until it reconnects."
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
