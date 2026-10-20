import XCTest
@testable import PipCore

final class MascotMoodTests: XCTestCase {
    func testThresholdsMatchDesign() {
        XCTAssertEqual(MascotMood.forRemaining(61), .healthy)
        XCTAssertEqual(MascotMood.forRemaining(60), .moderate)
        XCTAssertEqual(MascotMood.forRemaining(26), .moderate)
        XCTAssertEqual(MascotMood.forRemaining(25), .low)
        XCTAssertEqual(MascotMood.forRemaining(3), .low)
        XCTAssertEqual(MascotMood.forRemaining(2), .exhausted)
    }

    func testConnectionProblemsWinOverUsage() {
        XCTAssertEqual(MascotMood.resolve(status: .offline(reason: "x"), remaining: 90, recovering: true, resetsIn: nil), .disconnected)
        XCTAssertEqual(MascotMood.resolve(status: .loading, remaining: 90, recovering: false, resetsIn: nil), .loading)
        XCTAssertEqual(MascotMood.resolve(status: .stale(since: Date()), remaining: 90, recovering: false, resetsIn: nil), .stale)
    }

    func testExhaustedNapsWhenResetIsNear() {
        XCTAssertEqual(MascotMood.resolve(status: .live, remaining: 0, recovering: false, resetsIn: 10 * 60), .waiting)
        XCTAssertEqual(MascotMood.resolve(status: .live, remaining: 0, recovering: false, resetsIn: 3 * 3600), .exhausted)
        XCTAssertEqual(MascotMood.resolve(status: .live, remaining: 0, recovering: true, resetsIn: nil), .recovered)
    }

    func testNoQuotaIsNeutral() {
        XCTAssertEqual(MascotMood.resolve(status: .live, remaining: nil, recovering: false, resetsIn: nil), .healthy)
    }
}

final class PresenterTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func snapshot(_ metrics: [UsageMetric]) -> ProviderSnapshot {
        ProviderSnapshot(provider: .claudeCode, plan: "Max plan", metrics: metrics, fetchedAt: now, isDemo: true)
    }

    func testPercentRowRemainingAndUsed() {
        let snap = snapshot([.init(id: "s", label: "Session · 5-hour window", value: .quotaPercent(used: 62), resetsAt: now.addingTimeInterval(134 * 60))])
        let left = UsagePresenter(showUsed: false, now: now).rows(for: snap, status: .live, recovering: false)[0]
        XCTAssertEqual(left.big, "38%")
        XCTAssertEqual(left.word, "left")
        XCTAssertEqual(left.remaining, 38)
        XCTAssertEqual(left.sub?.hasPrefix("Resets in 2h 14m"), true)
        let used = UsagePresenter(showUsed: true, now: now).rows(for: snap, status: .live, recovering: false)[0]
        XCTAssertEqual(used.big, "62%")
        XCTAssertEqual(used.fraction ?? 0, 0.62, accuracy: 0.001)
    }

    func testOfflineHidesNumbers() {
        let snap = snapshot([.init(id: "s", label: "Session", value: .quotaPercent(used: 10))])
        let row = UsagePresenter(showUsed: false, now: now).rows(for: snap, status: .offline(reason: "x"), recovering: false)[0]
        XCTAssertEqual(row.big, "—")
        XCTAssertNil(row.fraction)
        XCTAssertEqual(row.mood, .disconnected)
    }

    func testMoneyAndUnknownAreNeverQuota() {
        let snap = snapshot([
            .init(id: "spend", label: "Spend", value: .spend(Money(8.72))),
            .init(id: "tpm", label: "TPM", value: .unknown, note: "Not reported"),
        ])
        XCTAssertNil(snap.remainingPercent)
        let rows = UsagePresenter(showUsed: false, now: now).rows(for: snap, status: .live, recovering: false)
        XCTAssertEqual(rows[0].big, "$8.72")
        XCTAssertNil(rows[0].fraction)
        XCTAssertEqual(rows[1].big, "—")
        XCTAssertEqual(rows[1].word, "unknown")
    }

    func testDurations() {
        XCTAssertEqual(TimeFormatting.duration(134 * 60), "2h 14m")
        XCTAssertEqual(TimeFormatting.duration(12 * 60), "12m")
        XCTAssertEqual(TimeFormatting.duration((2 * 1440 + 300) * 60), "2d 5h")
    }
}

final class OKLCHTests: XCTestCase {
    func testWhiteAndBlack() {
        let w = OKLCH(1, 0, 0).sRGB
        XCTAssertEqual(w.r, 1, accuracy: 0.002); XCTAssertEqual(w.g, 1, accuracy: 0.002); XCTAssertEqual(w.b, 1, accuracy: 0.002)
        let k = OKLCH(0, 0, 0).sRGB
        XCTAssertEqual(k.r, 0, accuracy: 0.002)
    }

    func testKnownRed() {
        // oklch(0.628 0.2577 29.23) is sRGB #FF0000.
        let red = OKLCH(0.628, 0.2577, 29.23).sRGB
        XCTAssertEqual(red.r, 1, accuracy: 0.01)
        XCTAssertEqual(red.g, 0, accuracy: 0.02)
        XCTAssertEqual(red.b, 0, accuracy: 0.02)
    }
}

@MainActor
final class CoordinatorTests: XCTestCase {
    func snap(used: Double, resetsAt: Date) -> ProviderSnapshot {
        ProviderSnapshot(provider: .claudeCode, plan: "", metrics: [.init(id: "s", label: "Session", value: .quotaPercent(used: used), resetsAt: resetsAt)],
                         fetchedAt: Date(), isDemo: true)
    }

    func makeCoordinator() -> UsageCoordinator {
        UsageCoordinator(providers: [MockUsageProvider(.claudeCode)], cache: SnapshotCache(key: "test.\(UUID())"))
    }

    func testResetIsDetectedAndCelebrated() {
        let c = makeCoordinator()
        var events: [UsageEvent] = []
        c.onEvent = { events.append($0) }
        let t = Date()
        c.apply(.success(snap(used: 100, resetsAt: t.addingTimeInterval(60))), for: .claudeCode)
        c.apply(.success(snap(used: 0, resetsAt: t.addingTimeInterval(5 * 3600))), for: .claudeCode)
        XCTAssertTrue(c.recovering.contains(.claudeCode))
        XCTAssertTrue(events.contains(.windowReset(.claudeCode)))
    }

    func testLowAlertsFireOncePerThreshold() {
        let c = makeCoordinator()
        var events: [UsageEvent] = []
        c.onEvent = { events.append($0) }
        let r = Date().addingTimeInterval(3600)
        c.apply(.success(snap(used: 81, resetsAt: r)), for: .claudeCode)
        c.apply(.success(snap(used: 82, resetsAt: r)), for: .claudeCode)
        c.apply(.success(snap(used: 96, resetsAt: r)), for: .claudeCode)
        XCTAssertEqual(events, [.runningLow(.claudeCode, remaining: 19, threshold: 20), .runningLow(.claudeCode, remaining: 4, threshold: 5)])
    }

    func testThreeFailuresGoOffline() {
        let c = makeCoordinator()
        c.apply(.success(snap(used: 10, resetsAt: Date().addingTimeInterval(3600))), for: .claudeCode)
        c.apply(.failure(ProviderError.network("x")), for: .claudeCode)
        if case .stale = c.status[.claudeCode] {} else { XCTFail("expected stale") }
        c.apply(.failure(ProviderError.network("x")), for: .claudeCode)
        c.apply(.failure(ProviderError.network("x")), for: .claudeCode)
        if case .offline = c.status[.claudeCode] {} else { XCTFail("expected offline") }
    }
}

/// Parsers checked against the example payloads in the official API references.
final class APIProviderTests: XCTestCase {
    struct Stub: HTTPClient {
        let routes: [String: (Int, String)]
        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            let (code, body) = routes[request.url!.path] ?? (404, "{}")
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!)
        }
    }
    struct Key: CredentialSource { var key: String? = "k"; func secret(for provider: ProviderID) -> String? { key } }

    func testAnthropicCostIsCentsAndTokensSum() async throws {
        let cost = #"{"data":[{"starting_at":"a","ending_at":"b","results":[{"amount":"123.78912","currency":"USD"}]}],"has_more":false,"next_page":null}"#
        let usage = #"{"data":[{"starting_at":"a","ending_at":"b","results":[{"cache_creation":{"ephemeral_1h_input_tokens":10,"ephemeral_5m_input_tokens":0},"cache_read_input_tokens":200,"output_tokens":500,"uncached_input_tokens":1500}]}],"has_more":false,"next_page":null}"#
        let p = AnthropicAPIProvider(credentials: Key(), client: Stub(routes: [
            "/v1/organizations/cost_report": (200, cost), "/v1/organizations/usage_report/messages": (200, usage)]))
        let snap = try await p.fetchUsage(now: Date())
        XCTAssertEqual(snap.metrics[0].value, .spend(Money(Decimal(string: "1.2378912")!)))
        XCTAssertEqual(snap.metrics[1].value, .tally(count: 2210, noun: "tokens"))
        XCTAssertNil(snap.remainingPercent, "spend-only providers must not invent a quota")
        XCTAssertFalse(snap.isDemo)
    }

    func testOpenAICostsSumExactly() async throws {
        let costs = #"{"object":"page","data":[{"object":"bucket","start_time":1,"end_time":2,"results":[{"object":"organization.costs.result","amount":{"value":0.06,"currency":"usd"}}]},{"object":"bucket","start_time":2,"end_time":3,"results":[{"object":"organization.costs.result","amount":{"value":8.66,"currency":"usd"}}]}],"has_more":false,"next_page":null}"#
        let usage = #"{"object":"page","data":[{"object":"bucket","start_time":1,"end_time":2,"results":[{"object":"organization.usage.completions.result","input_tokens":1000,"output_tokens":500,"num_model_requests":5}]}],"has_more":false,"next_page":null}"#
        let p = OpenAIAPIProvider(credentials: Key(), client: Stub(routes: [
            "/v1/organization/costs": (200, costs), "/v1/organization/usage/completions": (200, usage)]))
        let snap = try await p.fetchUsage(now: Date())
        XCTAssertEqual(snap.metrics[0].value, .spend(Money(Decimal(string: "8.72")!)))
        XCTAssertEqual(snap.metrics[1].value, .tally(count: 5, noun: "requests"))
    }

    func testAuthFailuresAndMissingKey() async {
        let p = OpenAIAPIProvider(credentials: Key(), client: Stub(routes: ["/v1/organization/costs": (401, "{}")]))
        do { _ = try await p.fetchUsage(now: Date()); XCTFail() } catch { XCTAssertEqual(error as? ProviderError, .unauthorized) }
        let none = AnthropicAPIProvider(credentials: Key(key: nil), client: Stub(routes: [:]))
        do { _ = try await none.fetchUsage(now: Date()); XCTFail() } catch { XCTAssertEqual(error as? ProviderError, .missingCredentials) }
    }
}

final class SubscriptionProviderTests: XCTestCase {
    func testClaudeLimitsArray() async throws {
        let body = #"{"limits":[{"kind":"session","percent":62,"resets_at":"2026-10-20T12:00:00.123Z"},{"kind":"weekly_all","percent":41,"resets_at":"2026-10-22T09:00:00Z"},{"kind":"weekly_scoped","percent":18,"resets_at":"2026-10-22T09:00:00Z","scope":{"model":{"display_name":"Opus","id":"claude-opus"}}},{"kind":"weekly_scoped","percent":null}],"extra_usage":null}"#
        let creds = #"{"claudeAiOauth":{"accessToken":"t","expiresAt":9999999999999,"subscriptionType":"max","rateLimitTier":"default_claude_max_20x"}}"#
        let p = ClaudeCodeProvider(client: APIProviderTests.Stub(routes: ["/api/oauth/usage": (200, body)]), readCredentials: { Data(creds.utf8) })
        let snap = try await p.fetchUsage(now: Date())
        XCTAssertEqual(snap.metrics.map(\.label), ["Session · 5-hour window", "Weekly · all models", "Weekly · Opus"])
        XCTAssertEqual(snap.remainingPercent, 38)
        XCTAssertNotNil(snap.metrics[0].resetsAt)
        XCTAssertEqual(snap.plan, "Max 20x plan")
    }

    func testClaudeLegacyFlatKeys() async throws {
        let body = #"{"five_hour":{"utilization":10,"resets_at":"2026-10-20T12:00:00Z"},"seven_day":{"utilization":30,"resets_at":null},"seven_day_opus":null}"#
        let creds = #"{"claudeAiOauth":{"accessToken":"t","subscriptionType":"pro"}}"#
        let p = ClaudeCodeProvider(client: APIProviderTests.Stub(routes: ["/api/oauth/usage": (200, body)]), readCredentials: { Data(creds.utf8) })
        let snap = try await p.fetchUsage(now: Date())
        XCTAssertEqual(snap.metrics.count, 2)
        XCTAssertEqual(snap.plan, "Pro plan")
    }

    func testClaudeExpiredTokenIsNotRefreshed() async {
        let creds = #"{"claudeAiOauth":{"accessToken":"t","expiresAt":1000}}"#
        let p = ClaudeCodeProvider(client: APIProviderTests.Stub(routes: [:]), readCredentials: { Data(creds.utf8) })
        do { _ = try await p.fetchUsage(now: Date()); XCTFail() } catch {
            XCTAssertTrue((error as? ProviderError)?.userMessage.contains("expired") == true)
        }
    }

    func testCodexReadsNewestEventAndRollsPastResets() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("codex-\(UUID())")
        let now = Date()
        // Codex names folders by Gregorian date, whatever the system calendar is.
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: now)
        let dir = home.appendingPathComponent(String(format: "sessions/%04d/%02d/%02d", c.year!, c.month!, c.day!))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let past = Int(now.timeIntervalSince1970) - 600, future = Int(now.timeIntervalSince1970) + 3600
        let lines = [
            #"{"timestamp":"2026-10-20T04:00:00.000Z","payload":{"rate_limits":{"primary":{"used_percent":90,"window_minutes":300,"resets_at":\#(future)}}}}"#,
            #"{"timestamp":"2026-10-20T04:37:26.096Z","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":13.0,"window_minutes":300,"resets_at":\#(future)},"secondary":{"used_percent":3.0,"window_minutes":10080,"resets_at":\#(past)},"credits":{"has_credits":false,"unlimited":false,"balance":"0"},"plan_type":"plus"}}}"#,
            #"{"timestamp":"2026-10-20T04:38:00.000Z","payload":{"type":"message"}}"#,
        ]
        try lines.joined(separator: "\n").write(to: dir.appendingPathComponent("rollout-a.jsonl"), atomically: true, encoding: .utf8)
        let snap = try await CodexLocalProvider(home: home).fetchUsage(now: now)
        XCTAssertEqual(snap.plan, "Plus plan")
        XCTAssertEqual(snap.metrics.map(\.label), ["5-hour window", "Weekly"])
        XCTAssertEqual(snap.metrics[0].value, .quotaPercent(used: 13))
        // The weekly window's reset already passed, so it refilled.
        XCTAssertEqual(snap.metrics[1].value, .quotaPercent(used: 0))
        XCTAssertGreaterThan(snap.metrics[1].resetsAt!, now)
    }

    func testCodexWithoutSessionsIsUnavailable() async {
        let p = CodexLocalProvider(home: URL(fileURLWithPath: "/nonexistent-\(UUID())"))
        do { _ = try await p.fetchUsage(now: Date()); XCTFail() } catch { XCTAssertNotNil(error as? ProviderError) }
    }

    func testCodexAppServerResult() throws {
        let now = Date(timeIntervalSince1970: 1_792_480_000)
        let json = #"{"rateLimits":{"primary":{"usedPercent":22,"windowDurationMins":300,"resetsAt":1792496357},"secondary":{"usedPercent":3,"windowDurationMins":10080,"resetsAt":1793083157},"credits":{"hasCredits":false,"unlimited":false,"balance":"0"},"planType":"plus"}}"#
        let snap = try CodexProvider.snapshot(fromResult: Data(json.utf8), now: now)
        XCTAssertEqual(snap.plan, "Plus plan")
        XCTAssertEqual(snap.fetchedAt, now)
        XCTAssertEqual(snap.metrics.map(\.label), ["5-hour window", "Weekly"])
        XCTAssertEqual(snap.metrics.first?.value, .quotaPercent(used: 22))
        XCTAssertFalse(snap.isDemo)
    }
}
