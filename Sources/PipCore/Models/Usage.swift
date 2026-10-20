import Foundation

public struct Money: Codable, Sendable, Equatable {
    public var amount: Decimal
    public var currencyCode: String

    public init(_ amount: Decimal, currencyCode: String = "USD") {
        self.amount = amount
        self.currencyCode = currencyCode
    }

    public var formatted: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        f.locale = Locale(identifier: "en_US")
        return f.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }
}

/// The value of one usage line. Each case is a different *kind* of number and
/// is presented differently; none of them is converted into another.
public enum MetricValue: Codable, Sendable, Equatable {
    /// Subscription quota window reported as a percentage (Claude Code, Codex).
    case quotaPercent(used: Double)
    /// Metered usage with a known ceiling, e.g. requests per day.
    case quotaCount(used: Int, limit: Int, noun: String)
    /// Metered usage with no ceiling, e.g. tokens today.
    case tally(count: Int, noun: String)
    /// Money spent in a billing period.
    case spend(Money)
    /// Prepaid balance.
    case credits(Money)
    /// The provider does not report this value. Never guess it.
    case unknown

    /// Fraction of the quota used, or nil when the metric has no ceiling.
    public var usedFraction: Double? {
        switch self {
        case .quotaPercent(let used): return min(1, max(0, used / 100))
        case .quotaCount(let used, let limit, _): return limit > 0 ? min(1, max(0, Double(used) / Double(limit))) : nil
        default: return nil
        }
    }

    public var isQuota: Bool { usedFraction != nil }
}

public struct UsageMetric: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var value: MetricValue
    /// When the quota window refills. Nil for metrics without a window.
    public var resetsAt: Date?
    /// Human reset label when the provider resets on a fixed schedule ("Thu 9:00 AM").
    public var resetLabel: String?
    public var note: String?

    public init(id: String, label: String, value: MetricValue, resetsAt: Date? = nil, resetLabel: String? = nil, note: String? = nil) {
        self.id = id
        self.label = label
        self.value = value
        self.resetsAt = resetsAt
        self.resetLabel = resetLabel
        self.note = note
    }
}

public struct ProviderSnapshot: Codable, Sendable, Equatable {
    public var provider: ProviderID
    public var plan: String
    public var metrics: [UsageMetric]
    public var fetchedAt: Date
    /// True when the numbers come from a demo provider rather than an account.
    public var isDemo: Bool

    public init(provider: ProviderID, plan: String, metrics: [UsageMetric], fetchedAt: Date, isDemo: Bool) {
        self.provider = provider
        self.plan = plan
        self.metrics = metrics
        self.fetchedAt = fetchedAt
        self.isDemo = isDemo
    }

    /// The metric that drives the mascot: the first quota-like line.
    public var primaryQuota: UsageMetric? { metrics.first { $0.value.isQuota } }

    /// Percent of the primary quota still available, 0...100, or nil when the
    /// provider has no quota (pure spend tracking).
    public var remainingPercent: Int? {
        guard let used = primaryQuota?.value.usedFraction else { return nil }
        return Int((100 * (1 - used)).rounded())
    }
}

public enum ConnectionStatus: Equatable, Sendable {
    case live
    case loading
    /// Showing cached data because recent refreshes failed.
    case stale(since: Date)
    case offline(reason: String)
    /// Hidden by the user.
    case paused
}
