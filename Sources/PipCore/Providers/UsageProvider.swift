import Foundation

public enum ProviderError: Error, Equatable, Sendable {
    case missingCredentials
    case unauthorized
    case network(String)
    case unsupported(String)

    public var userMessage: String {
        switch self {
        case .missingCredentials: return "No API key saved"
        case .unauthorized: return "The key was rejected"
        case .network(let m): return m
        case .unsupported(let m): return m
        }
    }
}

/// One source of usage data. Implementations must report only what the
/// provider actually returns; unavailable values are `.unknown`, never estimated.
public protocol UsageProvider: Sendable {
    var descriptor: ProviderDescriptor { get }
    /// Automatic refreshes are skipped until this much time has passed since the
    /// last attempt. A manual Refresh always goes through.
    var minimumRefreshInterval: TimeInterval { get }
    func fetchUsage(now: Date) async throws -> ProviderSnapshot
}

extension UsageProvider {
    public var minimumRefreshInterval: TimeInterval { 0 }
}
