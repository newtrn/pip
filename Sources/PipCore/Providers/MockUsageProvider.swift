import Foundation

/// Demo provider that reproduces the numbers from the approved design and lets
/// them drift slowly, so countdowns, low states and window resets can be seen
/// without an account. Every snapshot it returns is flagged `isDemo`.
public actor MockUsageProvider: UsageProvider {
    public nonisolated let descriptor: ProviderDescriptor

    /// A rolling quota window: usage grows linearly from `startUsed` and refills
    /// every `length` seconds.
    struct Window {
        var start: Date
        var startUsed: Double
        var ratePerHour: Double
        var length: TimeInterval
        var resetsAt: Date { start.addingTimeInterval(length) }

        mutating func used(at now: Date) -> Double {
            while now >= resetsAt {
                start = resetsAt
                startUsed = 0
            }
            return min(100, startUsed + ratePerHour * now.timeIntervalSince(start) / 3600)
        }
    }

    private var window: Window
    private var failNext = false

    public init(_ id: ProviderID, now: Date = Date()) {
        descriptor = .of(id)
        switch id {
        case .claudeCode:
            // 62% used, refills in 2h 14m — the design's Claude state.
            window = Window(start: now.addingTimeInterval(134 * 60 - 5 * 3600), startUsed: 62, ratePerHour: 3, length: 5 * 3600)
        case .codex:
            window = Window(start: now.addingTimeInterval(221 * 60 - 5 * 3600), startUsed: 23, ratePerHour: 2, length: 5 * 3600)
        case .openAIAPI:
            window = Window(start: Self.nextMidnightPT(after: now).addingTimeInterval(-86_400), startUsed: 41, ratePerHour: 0.6, length: 86_400)
        case .anthropicAPI:
            window = Window(start: now, startUsed: 0, ratePerHour: 0, length: 30 * 86_400)
        }
        // Anchor the start so `startUsed` is the value *now*, not at window start.
        window.startUsed -= window.ratePerHour * now.timeIntervalSince(window.start) / 3600
        window.startUsed = max(0, window.startUsed)
    }

    /// Demo control: put the primary window at a given percentage used.
    public func setUsedPercent(_ value: Double, now: Date = Date()) {
        window.startUsed = value - window.ratePerHour * now.timeIntervalSince(window.start) / 3600
    }

    /// Demo control: start a fresh window now, as if the provider reset it.
    public func resetWindow(now: Date = Date()) {
        window.start = now
        window.startUsed = 0
    }

    /// Demo control: make the next fetch fail, to exercise offline/stale states.
    public func failNextFetch() { failNext = true }

    public func fetchUsage(now: Date) async throws -> ProviderSnapshot {
        try await Task.sleep(nanoseconds: 350_000_000)
        if failNext {
            failNext = false
            throw ProviderError.network("Demo: simulated network failure")
        }
        let used = window.used(at: now)
        let metrics: [UsageMetric]
        let plan: String
        switch descriptor.id {
        case .claudeCode:
            plan = "Max plan"
            let weekly = Self.next(weekday: 5, hour: 9, after: now)
            metrics = [
                .init(id: "session", label: "Session · 5-hour window", value: .quotaPercent(used: used.rounded()), resetsAt: window.resetsAt),
                .init(id: "weekly", label: "Weekly · all models", value: .quotaPercent(used: 41), resetsAt: weekly),
                .init(id: "opus", label: "Weekly · Opus", value: .quotaPercent(used: 18), resetsAt: weekly),
            ]
        case .codex:
            plan = "Pro plan"
            metrics = [
                .init(id: "window", label: "5-hour window", value: .quotaPercent(used: used.rounded()), resetsAt: window.resetsAt),
                .init(id: "weekly", label: "Weekly", value: .quotaPercent(used: 57), resetsAt: Self.next(weekday: 2, hour: 6, after: now)),
                .init(id: "credits", label: "Credit balance", value: .credits(Money(12.40)), note: "Top-up credits · no expiry"),
            ]
        case .openAIAPI:
            plan = "API · Tier 1"
            metrics = [
                .init(id: "requests", label: "Requests today", value: .quotaCount(used: Int((used * 10).rounded()), limit: 1000, noun: "requests"),
                      resetsAt: window.resetsAt, resetLabel: "Midnight PT"),
                .init(id: "spend", label: "API spend · \(Self.monthName(now))", value: .spend(Money(8.72)), note: "No spending cap set"),
                .init(id: "tpm", label: "Tokens per minute", value: .unknown, note: "Not reported by this provider"),
            ]
        case .anthropicAPI:
            plan = "API · pay as you go"
            metrics = [
                .init(id: "spend", label: "API spend · \(Self.monthName(now))", value: .spend(Money(23.10)), note: "Month to date"),
                .init(id: "tokens", label: "Tokens today", value: .tally(count: 1_240_000, noun: "tokens")),
                .init(id: "limits", label: "Rate limits", value: .unknown, note: "Not reported by the usage API"),
            ]
        }
        return ProviderSnapshot(provider: descriptor.id, plan: plan, metrics: metrics, fetchedAt: now, isDemo: true)
    }

    // MARK: - Calendar helpers

    static func next(weekday: Int, hour: Int, after now: Date) -> Date {
        var c = DateComponents()
        c.weekday = weekday
        c.hour = hour
        return Calendar.current.nextDate(after: now, matching: c, matchingPolicy: .nextTime) ?? now.addingTimeInterval(86_400)
    }

    static func nextMidnightPT(after now: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        return cal.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) ?? now.addingTimeInterval(86_400)
    }

    static func monthName(_ now: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "LLLL"
        return f.string(from: now)
    }
}
