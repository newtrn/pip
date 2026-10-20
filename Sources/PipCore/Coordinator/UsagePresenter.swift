import Foundation

/// Turns snapshots into the strings and fractions the design shows. Colors are
/// applied by the UI layer from `remaining` and the provider hue.
public struct UsagePresenter {
    public var showUsed: Bool
    public var now: Date

    public init(showUsed: Bool, now: Date) {
        self.showUsed = showUsed
        self.now = now
    }

    public struct Row: Identifiable, Equatable {
        public let id: String
        public let label: String
        public let big: String
        public let word: String
        /// Fill fraction for bars and tubes, honouring "Numbers show: used".
        public let fraction: Double?
        /// Percent remaining, used to pick warning colors. Nil for non-quota rows.
        public let remaining: Int?
        public let sub: String?
        public let mood: MascotMood
        public let dimmed: Bool
        public let shimmer: Bool
    }

    public struct Header: Equatable {
        public let big: String
        public let unit: String
        public let word: String
        public let resetLine: String
        public let sentence: String
        public let windowShort: String
        public let fraction: Double
        public let remaining: Int?
        public let isQuota: Bool
    }

    public func resetAt(_ m: UsageMetric) -> String {
        if let label = m.resetLabel { return label }
        guard let d = m.resetsAt else { return "—" }
        return TimeFormatting.resetLabel(d, now: now)
    }

    public func resetIn(_ m: UsageMetric) -> String {
        guard let d = m.resetsAt else { return "—" }
        return TimeFormatting.duration(d.timeIntervalSince(now))
    }

    public func rows(for snapshot: ProviderSnapshot, status: ConnectionStatus, recovering: Bool, limit: Int? = nil) -> [Row] {
        let bad: Bool = { if case .offline = status { return true }; if case .paused = status { return true }; return false }()
        let loading = status == .loading
        let stale: Bool = { if case .stale = status { return true }; return false }()
        let metrics = limit.map { Array(snapshot.metrics.prefix($0)) } ?? snapshot.metrics
        return metrics.enumerated().map { i, m in
            var big: String, word: String, frac: Double? = nil, rem: Int? = nil, sub: String? = m.note
            switch m.value {
            case .quotaPercent(let used):
                let left = 100 - used
                rem = Int(left.rounded())
                big = "\(Int((showUsed ? used : left).rounded()))%"
                word = showUsed ? "used" : "left"
                frac = (showUsed ? used : left) / 100
                sub = quotaSub(m, empty: left <= 0 && i == 0)
            case .quotaCount(let used, let limit, _):
                let left = limit - used
                rem = limit > 0 ? Int((Double(left) / Double(limit) * 100).rounded()) : 0
                big = Self.grouped(showUsed ? used : left)
                word = showUsed ? "of \(Self.grouped(limit)) used" : "of \(Self.grouped(limit)) left"
                frac = limit > 0 ? Double(showUsed ? used : left) / Double(limit) : 0
                sub = quotaSub(m, empty: left <= 0 && i == 0)
            case .tally(let count, let noun):
                big = Self.compact(count); word = noun
            case .spend(let money):
                big = money.formatted; word = "spent"
            case .credits(let money):
                big = money.formatted; word = "balance"
            case .unknown:
                big = "—"; word = "unknown"
            }
            if bad {
                big = "—"; word = "unavailable"; frac = nil
                sub = i == 0 ? "Last known value hidden to avoid misleading you" : nil
            }
            if loading { big = "···"; word = "" }

            let mood: MascotMood
            if bad { mood = .disconnected }
            else if loading { mood = .loading }
            else if stale { mood = .stale }
            else if recovering && i == 0 { mood = .recovered }
            else if let rem {
                mood = MascotMood.resolve(status: .live, remaining: rem, recovering: false,
                                          resetsIn: i == 0 ? m.resetsAt?.timeIntervalSince(now) : nil)
            } else { mood = .healthy }

            return Row(id: m.id, label: m.label, big: big, word: word, fraction: frac, remaining: rem,
                       sub: sub, mood: mood, dimmed: stale || bad, shimmer: loading)
        }
    }

    private func quotaSub(_ m: UsageMetric, empty: Bool) -> String {
        empty ? "Empty · refills in \(resetIn(m)) (\(resetAt(m)))" : "Resets in \(resetIn(m)) · \(resetAt(m))"
    }

    public func header(for snapshot: ProviderSnapshot, providerName: String, status: ConnectionStatus, recovering: Bool) -> Header {
        let bad: Bool = { switch status { case .offline, .loading, .paused: return true; default: return false } }()
        guard let m = snapshot.primaryQuota else {
            let spend = snapshot.metrics.first
            let big: String = {
                switch spend?.value {
                case .spend(let money)?, .credits(let money)?: return money.formatted
                default: return "—"
                }
            }()
            return Header(big: bad ? "—" : big, unit: "", word: bad ? "" : "spent", resetLine: bad ? "—" : "month to date",
                          sentence: bad ? unreachableSentence(providerName, status) : "spent on \(providerName) so far. No quota to run out of.",
                          windowShort: "SPEND", fraction: 0, remaining: nil, isQuota: false)
        }
        let at = resetAt(m)
        var big: String, unit = "%", word: String, sentence: String, frac: Double, rem: Int
        let windowShort: String
        switch m.value {
        case .quotaCount(let used, let limit, let noun):
            let left = limit - used
            rem = Int((Double(left) / Double(max(1, limit)) * 100).rounded())
            big = Self.grouped(showUsed ? used : left); unit = ""
            word = showUsed ? "\(noun) used" : "\(noun) left"
            frac = Double(showUsed ? used : left) / Double(max(1, limit))
            sentence = "\(word) today on \(providerName), of \(Self.grouped(limit)). Resets at \(at)."
            windowShort = "DAILY"
        default:
            let used = (m.value.usedFraction ?? 0) * 100, left = 100 - used
            rem = Int(left.rounded())
            big = "\(Int((showUsed ? used : left).rounded()))"
            word = showUsed ? "used" : "left"
            frac = (showUsed ? used : left) / 100
            let window = m.label.split(separator: "·").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? m.label
            sentence = "of \(providerName)'s \(window) \(word). Refills at \(at)."
            windowShort = m.label.contains("5-hour") ? "5H" : m.label.lowercased().contains("week") ? "WEEKLY" : "WINDOW"
        }
        if bad {
            big = "—"; unit = ""; word = ""; frac = 0
            sentence = unreachableSentence(providerName, status)
        }
        let resetLine = bad ? "—" : recovering ? "Fresh window" : "refills in \(resetIn(m))"
        return Header(big: big, unit: unit, word: word, resetLine: resetLine, sentence: sentence,
                      windowShort: windowShort, fraction: frac, remaining: bad ? nil : rem, isQuota: true)
    }

    private func unreachableSentence(_ name: String, _ status: ConnectionStatus) -> String {
        status == .loading ? "Checking \(name)…" : "\(name) isn't answering. No numbers is better than wrong numbers."
    }

    /// Short value for tabs, the menu bar and Touch Bar: "38%", "—", "··", "$23".
    public func compactValue(for snapshot: ProviderSnapshot?, status: ConnectionStatus) -> String {
        switch status {
        case .offline, .paused: return "—"
        case .loading: return "··"
        default: break
        }
        guard let snapshot else { return "—" }
        if let rem = snapshot.remainingPercent { return "\(showUsed ? 100 - rem : rem)%" }
        if case .spend(let money)? = snapshot.metrics.first?.value {
            return "$" + String(Int((money.amount as NSDecimalNumber).doubleValue.rounded()))
        }
        return "—"
    }

    static func grouped(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    static func compact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.2fM", Double(n) / 1_000_000) }
        if n >= 10_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return grouped(n)
    }
}
