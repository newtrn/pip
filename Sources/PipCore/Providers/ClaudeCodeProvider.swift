import Foundation

/// Claude subscription limits from the endpoint Claude Code itself uses,
/// `GET https://api.anthropic.com/api/oauth/usage`, with the login Claude Code
/// already holds.
///
/// Undocumented (reviewed and accepted). Format per community tooling
/// (clanker-usage / ccusage 0.4.x): a `limits` array of
/// `{ kind: session | weekly_all | weekly_scoped, percent, resets_at, scope }`;
/// older responses used flat `five_hour` / `seven_day*` objects with `utilization`.
///
/// Pip never refreshes the token: Anthropic rotates refresh tokens, and a
/// refresh racing Claude Code's own would sign Claude Code out. An expired
/// token is reported, and Claude Code renews it the next time it runs.
public struct ClaudeCodeProvider: UsageProvider {
    public let descriptor = ProviderDescriptor.of(.claudeCode)
    public var minimumRefreshInterval: TimeInterval { 180 }
    let client: HTTPClient
    let readCredentials: @Sendable () -> Data?
    /// The last login read from the keychain, read again only once the token
    /// expires or is rejected, which is when Claude Code would have renewed it.
    private let cache = LoginCache()

    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    /// The edge rejects requests whose User-Agent isn't Claude Code's.
    static let userAgent = "claude-code/2.1.71"

    public init(client: HTTPClient = URLSession.shared, readCredentials: @escaping @Sendable () -> Data? = ClaudeCodeProvider.systemCredentials) {
        self.client = client
        self.readCredentials = readCredentials
    }

    struct Credentials: Decodable {
        struct OAuth: Decodable {
            let accessToken: String?
            let expiresAt: Double?
            let subscriptionType: String?
            let rateLimitTier: String?
        }
        let claudeAiOauth: OAuth?
    }

    struct Usage: Decodable {
        struct Limit: Decodable {
            struct Scope: Decodable {
                struct Model: Decodable { let display_name: String?; let id: String? }
                let model: Model?
            }
            let kind: String?
            let percent: Double?
            let resets_at: String?
            let scope: Scope?
        }
        struct Legacy: Decodable {
            let utilization: Double?
            let resets_at: String?
        }
        let limits: [Limit]?
        let five_hour: Legacy?
        let seven_day: Legacy?
        let seven_day_opus: Legacy?
    }

    public func fetchUsage(now: Date) async throws -> ProviderSnapshot {
        var oauth = cache.get()
        if oauth == nil || Self.isExpired(oauth!, now: now) {
            oauth = readCredentials().flatMap { try? JSONDecoder().decode(Credentials.self, from: $0).claudeAiOauth }
            cache.set(oauth)
        }
        guard let oauth, let token = oauth.accessToken, !token.isEmpty else {
            throw ProviderError.unsupported("Claude Code isn't signed in on this Mac")
        }
        if Self.isExpired(oauth, now: now) {
            throw ProviderError.unsupported("Claude Code's sign-in expired. Open Claude Code to renew it")
        }

        var request = URLRequest(url: Self.usageURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let usage: Usage
        do {
            usage = try await HTTP.get(Usage.self, request, client: client)
        } catch ProviderError.unauthorized {
            cache.set(nil)
            throw ProviderError.unsupported("No active Claude subscription, or the sign-in expired. Open Claude Code to renew it")
        }

        let metrics = Self.metrics(from: usage)
        guard !metrics.isEmpty else { throw ProviderError.unsupported("Claude didn't report any limits") }
        return ProviderSnapshot(provider: .claudeCode, plan: Self.plan(oauth), metrics: metrics, fetchedAt: now, isDemo: false)
    }

    static func isExpired(_ oauth: Credentials.OAuth, now: Date) -> Bool {
        oauth.expiresAt.map { $0 / 1000 < now.timeIntervalSince1970 } ?? false
    }

    static func metrics(from usage: Usage) -> [UsageMetric] {
        if let limits = usage.limits {
            return limits.enumerated().compactMap { i, limit in
                guard let percent = limit.percent else { return nil }
                let label: String
                switch limit.kind {
                case "session": label = "Session · 5-hour window"
                case "weekly_all": label = "Weekly · all models"
                case "weekly_scoped":
                    label = "Weekly · " + (limit.scope?.model?.display_name ?? limit.scope?.model?.id ?? "one model")
                default: label = (limit.kind ?? "Limit").replacingOccurrences(of: "_", with: " ").capitalized
                }
                return UsageMetric(id: "\(limit.kind ?? "limit")-\(i)", label: label, value: .quotaPercent(used: min(100, max(0, percent))),
                                   resetsAt: limit.resets_at.flatMap(parseDate))
            }
        }
        let legacy: [(String, String, Usage.Legacy?)] = [
            ("session", "Session · 5-hour window", usage.five_hour),
            ("weekly", "Weekly · all models", usage.seven_day),
            ("opus", "Weekly · Opus", usage.seven_day_opus),
        ]
        return legacy.compactMap { id, label, w in
            guard let used = w?.utilization else { return nil }
            return UsageMetric(id: id, label: label, value: .quotaPercent(used: min(100, max(0, used))), resetsAt: w?.resets_at.flatMap(parseDate))
        }
    }

    static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// "default_claude_max_20x" → "Max 20x plan", "pro" → "Pro plan".
    static func plan(_ oauth: Credentials.OAuth) -> String {
        let raw = oauth.rateLimitTier?.replacingOccurrences(of: "default_claude_", with: "") ?? oauth.subscriptionType ?? "Claude"
        let words = raw.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return words.joined(separator: " ") + " plan"
    }

    /// Claude Code keeps its login in the macOS keychain ("Claude Code-credentials");
    /// on other setups it uses `~/.claude/.credentials.json`. Claude Code writes the
    /// item with `/usr/bin/security`, so the item's access list always trusts that
    /// tool: reading through it never prompts, while reading the item directly
    /// prompts again whenever Pip's ad-hoc signature changes or the item is rewritten.
    public static let systemCredentials: @Sendable () -> Data? = {
        let security = Process()
        security.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        security.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe()
        security.standardOutput = out
        security.standardError = FileHandle.nullDevice
        if (try? security.run()) != nil {
            let data = out.fileHandleForReading.readDataToEndOfFile()
            security.waitUntilExit()
            if security.terminationStatus == 0, !data.isEmpty { return data }
        }
        let dir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        return try? Data(contentsOf: dir.appendingPathComponent(".credentials.json"))
    }
}

private final class LoginCache: @unchecked Sendable {
    private let lock = NSLock()
    private var oauth: ClaudeCodeProvider.Credentials.OAuth?

    func get() -> ClaudeCodeProvider.Credentials.OAuth? { lock.withLock { oauth } }
    func set(_ value: ClaudeCodeProvider.Credentials.OAuth?) { lock.withLock { oauth = value } }
}
