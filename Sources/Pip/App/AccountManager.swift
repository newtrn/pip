import Combine
import Foundation
import PipCore

/// Decides, per provider, whether Pip shows a real account or demo data, and
/// handles connecting and disconnecting. Nothing is read until the user connects.
@MainActor
final class AccountManager: ObservableObject {
    enum Method {
        /// A documented Admin API, with a key Pip stores in its own keychain item.
        case apiKey
        /// Claude Code's existing sign-in and its undocumented usage endpoint.
        case claudeCodeLogin
        /// Codex's existing sign-in, through its app-server (session logs as fallback).
        case codexLogin
    }

    static func method(for id: ProviderID) -> Method {
        switch id {
        case .openAIAPI, .anthropicAPI: return .apiKey
        case .claudeCode: return .claudeCodeLogin
        case .codex: return .codexLogin
        }
    }

    @Published private(set) var connected: Set<ProviderID> = []
    private let keychain: KeychainStore
    private let defaults: UserDefaults

    init(keychain: KeychainStore = KeychainStore(), defaults: UserDefaults = .standard) {
        self.keychain = keychain
        self.defaults = defaults
        connected = Set(ProviderID.allCases.filter { id in
            Self.method(for: id) == .apiKey ? keychain.read(id.rawValue) != nil : defaults.bool(forKey: Self.flagKey(id))
        })
    }

    private static func flagKey(_ id: ProviderID) -> String { "connected.\(id.rawValue)" }

    /// The data source to use for each provider at launch.
    func makeProviders() -> [any UsageProvider] {
        ProviderID.allCases.map { id in connected.contains(id) ? realProvider(id, key: nil) : MockUsageProvider(id) }
    }

    func isConnected(_ id: ProviderID) -> Bool { connected.contains(id) }

    /// Checks the source with one real fetch before switching to it, so a typo
    /// or a missing sign-in never replaces demo data with an error. Returns an
    /// error message, or nil on success.
    func connect(_ id: ProviderID, key raw: String?, coordinator: UsageCoordinator) async -> String? {
        let method = Self.method(for: id)
        let key = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if method == .apiKey && key.isEmpty { return "Paste a key first." }
        let probe = realProvider(id, key: method == .apiKey ? key : nil)
        do {
            _ = try await probe.fetchUsage(now: Date())
        } catch let error as ProviderError {
            if method == .apiKey, error == .unauthorized {
                return "That key was rejected. Usage data needs an Admin key, not a regular API key."
            }
            return error.userMessage
        } catch {
            return error.localizedDescription
        }
        if method == .apiKey {
            guard keychain.write(key, for: id.rawValue) else { return "Couldn't save the key to the keychain." }
        } else {
            defaults.set(true, forKey: Self.flagKey(id))
        }
        connected.insert(id)
        coordinator.replaceProvider(realProvider(id, key: nil))
        return nil
    }

    func disconnect(_ id: ProviderID, coordinator: UsageCoordinator) {
        if Self.method(for: id) == .apiKey { keychain.delete(id.rawValue) } else { defaults.removeObject(forKey: Self.flagKey(id)) }
        connected.remove(id)
        coordinator.replaceProvider(MockUsageProvider(id))
    }

    /// `key` overrides the keychain, for validating a key before it is saved.
    private func realProvider(_ id: ProviderID, key: String?) -> any UsageProvider {
        let credentials: CredentialSource = key.map { StaticCredential(key: $0) } ?? keychain
        switch id {
        case .openAIAPI: return OpenAIAPIProvider(credentials: credentials)
        case .anthropicAPI: return AnthropicAPIProvider(credentials: credentials)
        case .claudeCode: return ClaudeCodeProvider()
        case .codex: return CodexProvider()
        }
    }
}

/// A key held in memory only, used to validate before saving.
private struct StaticCredential: CredentialSource {
    let key: String
    func secret(for provider: ProviderID) -> String? { key }
}
