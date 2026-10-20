import Foundation

/// Anthropic API usage via the documented Usage and Cost Admin API
/// (platform.claude.com/docs/en/manage-claude/usage-cost-api).
///
/// Needs an Admin API key (`sk-ant-admin01-…`); workspace keys are rejected.
/// The API reports spend and tokens only. There is no quota or spend ceiling
/// in it, so Pip shows no percentage for this provider.
public struct AnthropicAPIProvider: UsageProvider {
    public let descriptor = ProviderDescriptor.of(.anthropicAPI)
    let credentials: CredentialSource
    let client: HTTPClient
    let baseURL: URL

    public init(credentials: CredentialSource, client: HTTPClient = URLSession.shared,
                baseURL: URL = URL(string: "https://api.anthropic.com")!) {
        self.credentials = credentials
        self.client = client
        self.baseURL = baseURL
    }

    struct Page<Item: Decodable>: Decodable {
        struct Bucket: Decodable {
            let starting_at: String
            let ending_at: String
            let results: [Item]
        }
        let data: [Bucket]
        let has_more: Bool
        let next_page: String?
    }

    struct CostItem: Decodable {
        /// Lowest currency units (cents) as a decimal string: "123.45" is $1.23.
        let amount: String
        let currency: String
    }

    struct UsageItem: Decodable {
        struct CacheCreation: Decodable {
            let ephemeral_1h_input_tokens: Int?
            let ephemeral_5m_input_tokens: Int?
        }
        let uncached_input_tokens: Int
        let cache_read_input_tokens: Int
        let output_tokens: Int
        let cache_creation: CacheCreation?

        var total: Int {
            uncached_input_tokens + cache_read_input_tokens + output_tokens
                + (cache_creation?.ephemeral_1h_input_tokens ?? 0) + (cache_creation?.ephemeral_5m_input_tokens ?? 0)
        }
    }

    public func fetchUsage(now: Date) async throws -> ProviderSnapshot {
        guard let key = credentials.secret(for: .anthropicAPI), !key.isEmpty else { throw ProviderError.missingCredentials }
        let iso = ISO8601DateFormatter()

        var cents = Decimal(0)
        var currency = "USD"
        var page: String?
        repeat {
            var query = [URLQueryItem(name: "starting_at", value: iso.string(from: HTTP.monthStart(now))),
                         URLQueryItem(name: "limit", value: "31")]
            if let page { query.append(URLQueryItem(name: "page", value: page)) }
            let result = try await HTTP.get(Page<CostItem>.self, request("/v1/organizations/cost_report", query, key: key), client: client)
            for item in result.data.flatMap(\.results) {
                cents += Decimal(string: item.amount) ?? 0
                currency = item.currency
            }
            page = result.has_more ? result.next_page : nil
        } while page != nil

        let usage = try await HTTP.get(Page<UsageItem>.self, request("/v1/organizations/usage_report/messages", [
            URLQueryItem(name: "starting_at", value: iso.string(from: HTTP.dayStart(now))),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: "1"),
        ], key: key), client: client)
        let tokensToday = usage.data.flatMap(\.results).reduce(0) { $0 + $1.total }

        return ProviderSnapshot(provider: .anthropicAPI, plan: "API · admin key", metrics: [
            UsageMetric(id: "spend", label: "API spend · \(HTTP.monthName(now))", value: .spend(Money(cents / 100, currencyCode: currency)),
                        note: "Month to date (UTC) · Priority Tier not included"),
            UsageMetric(id: "tokens", label: "Tokens today (UTC)", value: .tally(count: tokensToday, noun: "tokens"),
                        note: "Input, cache and output tokens"),
            UsageMetric(id: "limits", label: "Rate limits", value: .unknown, note: "Not reported by the usage API"),
        ], fetchedAt: now, isDemo: false)
    }

    func request(_ path: String, _ query: [URLQueryItem], key: String) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        var r = URLRequest(url: components.url!)
        r.setValue(key, forHTTPHeaderField: "x-api-key")
        r.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        r.setValue(HTTP.userAgent, forHTTPHeaderField: "User-Agent")
        r.timeoutInterval = 20
        return r
    }
}
