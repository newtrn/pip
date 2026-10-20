import Foundation

/// Pip's emotional states, straight from the design's state list.
public enum MascotMood: String, CaseIterable, Sendable {
    case healthy, moderate, low, exhausted, waiting, recovered, disconnected, loading, stale

    /// Remaining-percent thresholds from the design: >60 healthy, >25 moderate,
    /// >2 low, otherwise exhausted.
    public static func forRemaining(_ remaining: Int) -> MascotMood {
        remaining > 60 ? .healthy : remaining > 25 ? .moderate : remaining > 2 ? .low : .exhausted
    }

    /// Resolves the mood for a provider. Connection problems win over usage,
    /// a fresh refill wins over everything else, and an exhausted window that is
    /// about to refill turns into a nap.
    public static func resolve(status: ConnectionStatus, remaining: Int?, recovering: Bool, resetsIn: TimeInterval?) -> MascotMood {
        switch status {
        case .offline: return .disconnected
        case .paused: return .disconnected
        case .loading: return .loading
        case .stale: return .stale
        case .live: break
        }
        if recovering { return .recovered }
        guard let remaining else { return .healthy }
        let mood = forRemaining(remaining)
        if mood == .exhausted, let resetsIn, resetsIn <= 30 * 60 { return .waiting }
        return mood
    }

    /// Eyes blink only in the awake, resting states.
    public var blinks: Bool { [.healthy, .moderate, .low, .stale].contains(self) }

    /// Liquid is drained when Pip has no trustworthy number to show.
    public var hidesLiquid: Bool { self == .disconnected || self == .loading }
}

/// Body-shape targets per mood (slime.js `T`). The renderer eases toward these.
public struct SlimeShapeTarget: Sendable, Equatable {
    public var sx: Double, sy: Double, amp: Double, spd: Double

    public static func of(_ mood: MascotMood) -> SlimeShapeTarget {
        switch mood {
        case .healthy: return .init(sx: 1, sy: 1, amp: 0.6, spd: 1.6)
        case .moderate: return .init(sx: 1.05, sy: 0.9, amp: 0.45, spd: 1.25)
        case .low: return .init(sx: 1.14, sy: 0.76, amp: 0.35, spd: 0.85)
        case .exhausted: return .init(sx: 1.3, sy: 0.56, amp: 0.28, spd: 0.7)
        case .waiting: return .init(sx: 1.26, sy: 0.6, amp: 0.18, spd: 0.45)
        case .recovered: return .init(sx: 0.93, sy: 1.1, amp: 1, spd: 2.8)
        case .disconnected: return .init(sx: 1.06, sy: 0.84, amp: 0.06, spd: 0.35)
        case .loading: return .init(sx: 1, sy: 0.95, amp: 0.75, spd: 3.2)
        case .stale: return .init(sx: 1.04, sy: 0.9, amp: 0.18, spd: 0.55)
        }
    }
}

/// Pip's voice. Copy is taken verbatim from the design.
public enum MascotVoice {
    public static func line(_ mood: MascotMood, providerName: String, remaining: Int?, resetAt: String, resetIn: String, staleMinutes: Int) -> String {
        guard let remaining else {
            switch mood {
            case .disconnected: return "Can't reach \(providerName). Did the key expire?"
            case .loading: return "Checking the meters…"
            case .stale: return "These numbers are \(staleMinutes) min old. Grain of salt."
            default: return "No quota here — just keeping count."
            }
        }
        switch mood {
        case .healthy: return "Full tank. \(remaining)% left — let's build something."
        case .moderate: return "Pacing myself. \(remaining)% of the window left."
        case .low: return "Running on fumes. \(remaining)% left until \(resetAt)."
        case .exhausted: return "Tapped out. \(providerName) refills at \(resetAt)."
        case .waiting: return "Napping till reset. Wake me in \(resetIn)."
        case .recovered: return "Refilled! Fresh window, full tank."
        case .disconnected: return "Can't reach \(providerName). Did the key expire?"
        case .loading: return "Checking the meters…"
        case .stale: return "These numbers are \(staleMinutes) min old. Grain of salt."
        }
    }
}
