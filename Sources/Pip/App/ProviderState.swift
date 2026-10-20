import PipCore
import SwiftUI

/// Everything a view needs about one provider at this moment.
struct ProviderState: Identifiable {
    let descriptor: ProviderDescriptor
    let snapshot: ProviderSnapshot?
    let status: ConnectionStatus
    let recovering: Bool
    let now: Date

    var id: ProviderID { descriptor.id }
    var hue: Double { descriptor.hue }
    var remaining: Int? { snapshot?.remainingPercent }
    var isLive: Bool { status == .live }
    var isUnavailable: Bool {
        switch status { case .offline, .loading, .paused: return true; default: return false }
    }

    var mood: MascotMood {
        MascotMood.resolve(status: status, remaining: remaining, recovering: recovering,
                           resetsIn: snapshot?.primaryQuota?.resetsAt?.timeIntervalSince(now))
    }

    var staleMinutes: Int {
        if case .stale(let since) = status { return max(1, Int(now.timeIntervalSince(since) / 60)) }
        return 0
    }

    func line(presenter: UsagePresenter) -> String {
        let quota = snapshot?.primaryQuota
        return MascotVoice.line(mood, providerName: descriptor.name, remaining: remaining,
                                resetAt: quota.map(presenter.resetAt) ?? "—",
                                resetIn: quota.map(presenter.resetIn) ?? "—",
                                staleMinutes: staleMinutes)
    }
}

extension UsageCoordinator {
    func state(_ id: ProviderID) -> ProviderState {
        ProviderState(descriptor: .of(id), snapshot: snapshots[id], status: status[id] ?? .loading,
                      recovering: recovering.contains(id), now: now)
    }
}
