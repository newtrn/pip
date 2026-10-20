import Combine
import ServiceManagement

/// Wraps SMAppService so the toggle always reflects the real login-item state.
@MainActor
final class LaunchAtLogin: ObservableObject {
    @Published private(set) var isEnabled = SMAppService.mainApp.status == .enabled
    @Published private(set) var problem: String?

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            problem = SMAppService.mainApp.status == .requiresApproval ? "Approve Pip in System Settings → Login Items" : nil
        } catch {
            problem = "Couldn't change the login item: \(error.localizedDescription)"
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
