import Foundation

/// Codex subscription limits, asked live from Codex itself: Pip starts
/// `codex app-server` (the JSON-RPC server Codex's own apps use) and calls
/// `account/rateLimits/read`. Codex answers with its existing sign-in, so Pip
/// never sees a token.
///
/// Undocumented (reviewed and accepted). If no Codex binary is found or the
/// call fails, the session logs are used instead, and their age is shown as is.
public struct CodexProvider: UsageProvider {
    public let descriptor = ProviderDescriptor.of(.codex)
    public var minimumRefreshInterval: TimeInterval { 120 }
    let binary: URL?
    let logs: CodexLocalProvider
    let timeout: TimeInterval

    public init(binary: URL? = CodexProvider.findBinary(), logs: CodexLocalProvider = CodexLocalProvider(), timeout: TimeInterval = 20) {
        self.binary = binary
        self.logs = logs
        self.timeout = timeout
    }

    public func fetchUsage(now: Date) async throws -> ProviderSnapshot {
        guard let binary else { return try await logs.fetchUsage(now: now) }
        do {
            let data = try await AppServer.call(binary: binary, method: "account/rateLimits/read", timeout: timeout)
            return try Self.snapshot(fromResult: data, now: now)
        } catch {
            // Fall back to the logs, but keep the live error if they have nothing either.
            if let snap = try? await logs.fetchUsage(now: now) { return snap }
            throw error
        }
    }

    struct RateLimitsResult: Decodable {
        struct Snapshot: Decodable {
            struct Window: Decodable {
                let usedPercent: Double
                let windowDurationMins: Int?
                let resetsAt: Double?
            }
            struct Credits: Decodable {
                let hasCredits: Bool?
                let unlimited: Bool?
                let balance: String?
            }
            let primary: Window?
            let secondary: Window?
            let credits: Credits?
            let planType: String?
        }
        let rateLimits: Snapshot?
    }

    static func snapshot(fromResult data: Data, now: Date) throws -> ProviderSnapshot {
        guard let live = try JSONDecoder().decode(RateLimitsResult.self, from: data).rateLimits else {
            throw ProviderError.unsupported("Codex did not report limits")
        }
        func window(_ w: RateLimitsResult.Snapshot.Window?) -> CodexLocalProvider.RateLimits.Window? {
            w.map { .init(used_percent: $0.usedPercent, window_minutes: $0.windowDurationMins, resets_at: $0.resetsAt) }
        }
        let limits = CodexLocalProvider.RateLimits(
            primary: window(live.primary), secondary: window(live.secondary),
            credits: live.credits.map { .init(has_credits: $0.hasCredits, unlimited: $0.unlimited, balance: $0.balance) },
            plan_type: live.planType)
        return try CodexLocalProvider.snapshot(from: limits, observedAt: now, now: now)
    }

    /// A native Codex binary first (apps launched from Finder get a minimal
    /// PATH, and npm's `codex` is a Node script), then the usual install spots.
    public static func findBinary() -> URL? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        var candidates = [
            ProcessInfo.processInfo.environment["CODEX_BIN"],
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.local/bin/codex",
            "\(home)/.cargo/bin/codex",
        ].compactMap { $0 }
        candidates += (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/codex" }
        return candidates.first { fm.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }
}

/// One short-lived `codex app-server` session over stdio: initialize, one
/// request, then the process is ended.
enum AppServer {
    static func call(binary: URL, method: String, timeout: TimeInterval) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                cont.resume(with: Result { try run(binary: binary, method: method, timeout: timeout) })
            }
        }
    }

    private struct Response: Decodable {
        struct RPCError: Decodable { let message: String? }
        let id: Int?
        let error: RPCError?
    }

    private final class Watchdog: @unchecked Sendable {
        let process: Process
        init(_ process: Process) { self.process = process }
        func fire() { if process.isRunning { process.terminate() } }
    }

    private static func run(binary: URL, method: String, timeout: TimeInterval) throws -> Data {
        // A Codex that exits early must not take Pip down with SIGPIPE.
        signal(SIGPIPE, SIG_IGN)
        let process = Process()
        process.executableURL = binary
        process.arguments = ["app-server"]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw ProviderError.unsupported("Couldn't start Codex") }

        let watchdog = Watchdog(process)
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { watchdog.fire() }
        defer {
            try? input.fileHandleForWriting.close()
            watchdog.fire()
            process.waitUntilExit()
        }

        func send(_ message: [String: Any]) throws {
            var line = try JSONSerialization.data(withJSONObject: message)
            line.append(0x0A)
            try input.fileHandleForWriting.write(contentsOf: line)
        }

        var buffer = Data()
        /// Reads lines until the response with `id` arrives; notifications are skipped.
        func response(_ id: Int) throws -> Data {
            while true {
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let line = buffer[buffer.startIndex..<nl]
                    buffer.removeSubrange(buffer.startIndex...nl)
                    guard let r = try? JSONDecoder().decode(Response.self, from: line), r.id == id else { continue }
                    if let e = r.error { throw ProviderError.unsupported(e.message.map { "Codex: \($0)" } ?? "Codex returned an error") }
                    guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any], let result = object["result"] else {
                        throw ProviderError.unsupported("Codex returned no result")
                    }
                    return try JSONSerialization.data(withJSONObject: result)
                }
                let chunk = output.fileHandleForReading.availableData
                if chunk.isEmpty { throw ProviderError.network("Codex didn't answer in time") }
                buffer.append(chunk)
            }
        }

        try send(["method": "initialize", "id": 1, "params": ["clientInfo": ["name": "pip", "title": "Pip", "version": "1.0"]]])
        _ = try response(1)
        try send(["method": "initialized"])
        try send(["method": method, "id": 2])
        return try response(2)
    }
}
