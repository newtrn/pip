import Foundation

/// Stable identifier for every provider Pip knows about. Adding a provider means
/// adding a case here, a descriptor, and a `UsageProvider` implementation —
/// the UI never switches on specific providers.
public enum ProviderID: String, CaseIterable, Codable, Sendable, Identifiable {
    case claudeCode
    case codex
    case openAIAPI
    case anthropicAPI

    public var id: String { rawValue }
}

/// How a provider bills the user. Kept separate so quota windows, metered API
/// usage and prepaid credits are never mixed into one number.
public enum BillingModel: String, Codable, Sendable {
    case subscription
    case metered
}

public struct ProviderDescriptor: Sendable, Equatable {
    public let id: ProviderID
    /// Full name used in sentences ("Can't reach Claude Code").
    public let name: String
    /// Narrow name for tabs and Touch Bar buttons.
    public let tabName: String
    /// Single glyph for the multi-provider menu bar layout.
    public let short: String
    /// OKLCH hue used to derive every tint for this provider.
    public let hue: Double
    public let billing: BillingModel
    /// What this provider is able to report, shown in Settings.
    public let reports: String

    public init(id: ProviderID, name: String, tabName: String, short: String, hue: Double, billing: BillingModel, reports: String) {
        self.id = id
        self.name = name
        self.tabName = tabName
        self.short = short
        self.hue = hue
        self.billing = billing
        self.reports = reports
    }
}

extension ProviderDescriptor {
    public static func of(_ id: ProviderID) -> ProviderDescriptor {
        switch id {
        case .claudeCode:
            return .init(id: id, name: "Claude Code", tabName: "Claude", short: "C", hue: 45, billing: .subscription,
                         reports: "5-hour session · weekly · Opus weekly")
        case .codex:
            return .init(id: id, name: "Codex", tabName: "Codex", short: "X", hue: 250, billing: .subscription,
                         reports: "5-hour · weekly · credit balance")
        case .openAIAPI:
            return .init(id: id, name: "OpenAI API", tabName: "OpenAI", short: "O", hue: 160, billing: .metered,
                         reports: "Daily requests · spend · TPM unknown")
        case .anthropicAPI:
            return .init(id: id, name: "Anthropic API", tabName: "Anthropic", short: "A", hue: 305, billing: .metered,
                         reports: "Spend · tokens · no quota")
        }
    }
}
