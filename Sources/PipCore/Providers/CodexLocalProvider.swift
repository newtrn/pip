import Foundation

/// Codex subscription limits, read from the session logs Codex writes locally
/// (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`). Every turn logs a
/// `rate_limits` object with the 5-hour and weekly windows.
///
/// Undocumented format (reviewed and accepted). No network, no credentials:
/// the numbers are as fresh as the last Codex turn, and Pip says so.
public struct CodexLocalProvider: UsageProvider {
    public let descriptor = ProviderDescriptor.of(.codex)
    let home: URL
    /// How many days of session folders to search for the latest event.
    let lookbackDays: Int

    public init(home: URL? = nil, lookbackDays: Int = 14) {
        let env = ProcessInfo.processInfo.environment["CODEX_HOME"]
        self.home = home ?? env.map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        self.lookbackDays = lookbackDays
    }

    struct Event: Decodable {
        let timestamp: String?
        let payload: Payload?
        struct Payload: Decodable { let rate_limits: RateLimits? }
    }

    struct RateLimits: Decodable {
        struct Window: Decodable {
            let used_percent: Double
            let window_minutes: Int?
            let resets_at: Double?
        }
        struct Credits: Decodable {
            let has_credits: Bool?
            let unlimited: Bool?
            let balance: String?
        }
        let primary: Window?
        let secondary: Window?
        let credits: Credits?
        let plan_type: String?
    }

    public func fetchUsage(now: Date) async throws -> ProviderSnapshot {
        guard let (limits, observedAt) = latestRateLimits(now: now) else {
            throw ProviderError.unsupported("No recent Codex sessions found. Run Codex once to report limits.")
        }
        return try Self.snapshot(from: limits, observedAt: observedAt, now: now)
    }

    /// Shared with `CodexProvider`, which gets the same numbers live from Codex.
    static func snapshot(from limits: RateLimits, observedAt: Date, now: Date) throws -> ProviderSnapshot {
        var metrics: [UsageMetric] = []
        for (id, window) in [("primary", limits.primary), ("secondary", limits.secondary)] {
            guard let window else { continue }
            var used = window.used_percent
            var resetsAt = window.resets_at.map { Date(timeIntervalSince1970: $0) }
            // The reading predates a reset: that window has since refilled. Usage
            // after the reset from other clients isn't visible locally.
            if let r = resetsAt, r <= now, let minutes = window.window_minutes {
                used = 0
                var next = r
                while next <= now { next.addTimeInterval(Double(minutes) * 60) }
                resetsAt = next
            }
            metrics.append(UsageMetric(id: id, label: Self.label(minutes: window.window_minutes), value: .quotaPercent(used: used),
                                       resetsAt: resetsAt))
        }
        if let credits = limits.credits, credits.has_credits == true || credits.unlimited == true {
            metrics.append(credits.unlimited == true
                ? UsageMetric(id: "credits", label: "Credits", value: .unknown, note: "Unlimited")
                : UsageMetric(id: "credits", label: "Credits", value: .tally(count: Int(Double(credits.balance ?? "") ?? 0), noun: "credits"),
                              note: "Top-up credits"))
        }
        guard !metrics.isEmpty else { throw ProviderError.unsupported("Codex did not report limits") }
        let plan = limits.plan_type.map { $0.prefix(1).uppercased() + $0.dropFirst() + " plan" } ?? "ChatGPT plan"
        return ProviderSnapshot(provider: .codex, plan: plan, metrics: metrics, fetchedAt: observedAt, isDemo: false)
    }

    static func label(minutes: Int?) -> String {
        switch minutes {
        case 300?: return "5-hour window"
        case 10080?: return "Weekly"
        case 1440?: return "Daily"
        case let m?: return m % 1440 == 0 ? "\(m / 1440)-day window" : "\(m / 60)-hour window"
        case nil: return "Usage window"
        }
    }

    /// The newest `rate_limits` event across recent session files.
    func latestRateLimits(now: Date) -> (RateLimits, Date)? {
        let fm = FileManager.default
        let sessions = home.appendingPathComponent("sessions")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        var files: [(URL, Date)] = []
        for offset in 0..<lookbackDays {
            guard let day = cal.date(byAdding: .day, value: -offset, to: now) else { continue }
            let c = cal.dateComponents([.year, .month, .day], from: day)
            let dir = sessions.appendingPathComponent(String(format: "%04d/%02d/%02d", c.year!, c.month!, c.day!))
            guard let names = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for url in names where url.pathExtension == "jsonl" {
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                files.append((url, modified))
            }
            if files.count >= 8 { break }
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for (url, modified) in files.sorted(by: { $0.1 > $1.1 }) {
            guard let tail = Self.tail(of: url, bytes: 512 * 1024) else { continue }
            for line in tail.split(separator: "\n").reversed() where line.contains("\"rate_limits\"") {
                guard let event = try? JSONDecoder().decode(Event.self, from: Data(line.utf8)),
                      let limits = event.payload?.rate_limits, limits.primary != nil || limits.secondary != nil else { continue }
                let at = event.timestamp.flatMap { iso.date(from: $0) } ?? modified
                return (limits, at)
            }
        }
        return nil
    }

    /// The last `bytes` of a file: rate limit events are appended, so the newest is near the end.
    static func tail(of url: URL, bytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
