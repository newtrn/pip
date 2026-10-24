import Combine
import Foundation
import os

/// Events worth telling the user about outside the popover.
public enum UsageEvent: Equatable, Sendable {
    case runningLow(ProviderID, remaining: Int, threshold: Int)
    case windowReset(ProviderID)
    case connectionLost(ProviderID)
}

/// Owns provider polling, the last known snapshots, connection status and the
/// transient "recovered" reaction. UI observes it; it knows nothing about UI.
@MainActor
public final class UsageCoordinator: ObservableObject {
    @Published public private(set) var snapshots: [ProviderID: ProviderSnapshot] = [:]
    @Published public private(set) var status: [ProviderID: ConnectionStatus] = [:]
    @Published public private(set) var recovering: Set<ProviderID> = []
    /// Providers whose app needs to sign in again. Checked every minute,
    /// regardless of their usual minimum interval, since nothing is sent.
    @Published public private(set) var needsSignIn: Set<ProviderID> = []
    /// Ticks every 30 s so countdowns stay current without per-second redraws.
    @Published public private(set) var now = Date()

    public private(set) var providers: [ProviderID: any UsageProvider]
    public var onEvent: ((UsageEvent) -> Void)?

    private let cache: SnapshotCache
    private let refreshInterval: TimeInterval
    private var failures: [ProviderID: Int] = [:]
    private var lastAttempt: [ProviderID: Date] = [:]
    private var lastLowThreshold: [ProviderID: Int] = [:]
    private var refreshTasks: [ProviderID: Task<Void, Never>] = [:]
    private var timer: Timer?
    private var clock: Timer?
    /// Keeps App Nap from stretching the polling timer to many minutes while
    /// Pip has no window on screen, which is most of the time.
    private var activity: NSObjectProtocol?
    private let log = Logger(subsystem: "dev.pip.Pip", category: "refresh")

    public static let lowThresholds = [20, 5]
    static let recoveredDuration: TimeInterval = 3.6

    public init(providers: [any UsageProvider], cache: SnapshotCache = SnapshotCache(), refreshInterval: TimeInterval = 60) {
        var map: [ProviderID: any UsageProvider] = [:]
        for p in providers { map[p.descriptor.id] = p }
        self.providers = map
        self.cache = cache
        self.refreshInterval = refreshInterval
        // Never show cached demo numbers for a real account, or the reverse.
        for (id, snap) in cache.load() where map[id] != nil && snap.isDemo == (map[id] is MockUsageProvider) {
            snapshots[id] = snap
            status[id] = .stale(since: snap.fetchedAt)
        }
    }

    public func start() {
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep],
                                                          reason: "Polling AI usage")
        refreshAll()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshAll() }
        }
        timer?.tolerance = refreshInterval * 0.2
        clock = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.now = Date() }
        }
        clock?.tolerance = 5
    }

    public func stop() {
        timer?.invalidate()
        clock?.invalidate()
        activity.map(ProcessInfo.processInfo.endActivity)
        activity = nil
        refreshTasks.values.forEach { $0.cancel() }
    }

    public func refreshAll() {
        for id in providers.keys { refresh(id, force: false) }
    }

    /// `force` is for the user's Refresh button; timers respect each provider's minimum interval.
    public func refresh(_ id: ProviderID, force: Bool = true) {
        guard let provider = providers[id], refreshTasks[id] == nil else { return }
        if !force, !needsSignIn.contains(id), let last = lastAttempt[id], Date().timeIntervalSince(last) < provider.minimumRefreshInterval { return }
        lastAttempt[id] = Date()
        log.debug("refresh \(id.rawValue, privacy: .public) force=\(force)")
        if snapshots[id] == nil || status[id] == .live { status[id] = .loading }
        // The task inherits main-actor isolation; only the fetch itself runs elsewhere.
        refreshTasks[id] = Task { [weak self] in
            let result: Result<ProviderSnapshot, Error>
            do { result = .success(try await provider.fetchUsage(now: Date())) } catch { result = .failure(error) }
            // A replaced provider's in-flight fetch must not land on the new one.
            guard let self, !Task.isCancelled else { return }
            self.refreshTasks[id] = nil
            self.apply(result, for: id)
        }
    }

    func apply(_ result: Result<ProviderSnapshot, Error>, for id: ProviderID) {
        now = Date()
        switch result {
        case .success(let snap):
            let previous = snapshots[id]
            snapshots[id] = snap
            status[id] = .live
            needsSignIn.remove(id)
            failures[id] = 0
            detectReset(id, previous: previous, current: snap)
            detectLow(id, current: snap)
            cache.save(snapshots)
        case .failure(let error):
            log.notice("\(id.rawValue, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            if case ProviderError.signInNeeded = error { needsSignIn.insert(id) } else { needsSignIn.remove(id) }
            let count = (failures[id] ?? 0) + 1
            failures[id] = count
            if let snap = snapshots[id], count < 3 {
                status[id] = .stale(since: snap.fetchedAt)
            } else {
                let reason = (error as? ProviderError)?.userMessage ?? error.localizedDescription
                status[id] = .offline(reason: reason)
            }
            if count == 3 { onEvent?(.connectionLost(id)) }
        }
    }

    /// A refill shows up as the primary window's reset moving forward while
    /// remaining jumps up. Pip celebrates for a few seconds.
    func detectReset(_ id: ProviderID, previous: ProviderSnapshot?, current: ProviderSnapshot) {
        guard let before = previous?.remainingPercent, let after = current.remainingPercent else { return }
        let windowMoved = {
            guard let a = previous?.primaryQuota?.resetsAt, let b = current.primaryQuota?.resetsAt else { return true }
            return b > a.addingTimeInterval(60)
        }()
        guard windowMoved, after - before >= 30 else { return }
        lastLowThreshold[id] = nil
        celebrate(id)
        onEvent?(.windowReset(id))
    }

    func detectLow(_ id: ProviderID, current: ProviderSnapshot) {
        guard let rem = current.remainingPercent else { return }
        let crossed = Self.lowThresholds.filter { rem <= $0 }.min()
        guard let crossed else { lastLowThreshold[id] = nil; return }
        if lastLowThreshold[id] == nil || crossed < lastLowThreshold[id]! {
            lastLowThreshold[id] = crossed
            onEvent?(.runningLow(id, remaining: rem, threshold: crossed))
        }
    }

    private func celebrate(_ id: ProviderID) {
        recovering.insert(id)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.recoveredDuration * 1_000_000_000))
            self?.recovering.remove(id)
        }
    }

    public func clearRecovering(_ id: ProviderID) { recovering.remove(id) }

    // MARK: - Demo controls

    /// Plays the design's "Simulate quota reset": drain to empty, then refill.
    public func simulateReset(_ id: ProviderID) {
        guard let mock = providers[id] as? MockUsageProvider else { return }
        Task {
            await mock.setUsedPercent(100)
            refresh(id)
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            await mock.resetWindow()
            refresh(id)
        }
    }

    public func simulateFailure(_ id: ProviderID) {
        guard let mock = providers[id] as? MockUsageProvider else { return }
        Task {
            await mock.failNextFetch()
            refresh(id)
        }
    }

    public var usesDemoData: Bool { providers.values.contains { $0 is MockUsageProvider } }

    public func isDemo(_ id: ProviderID) -> Bool { providers[id] is MockUsageProvider }

    /// Swaps the data source for one provider (e.g. demo → real after a key is
    /// saved). Old numbers are dropped so demo values never mix with real ones.
    public func replaceProvider(_ provider: any UsageProvider) {
        let id = provider.descriptor.id
        refreshTasks[id]?.cancel()
        refreshTasks[id] = nil
        providers[id] = provider
        snapshots[id] = nil
        status[id] = .loading
        failures[id] = 0
        lastAttempt[id] = nil
        needsSignIn.remove(id)
        lastLowThreshold[id] = nil
        recovering.remove(id)
        cache.save(snapshots)
        refresh(id)
    }
}
