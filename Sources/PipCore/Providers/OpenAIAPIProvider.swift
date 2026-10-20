import Foundation

/// OpenAI API usage via the documented organization Costs and Usage endpoints
/// (openai-openapi spec: `/organization/costs`, `/organization/usage/completions`).
///
/// Needs an Admin key (bearer auth). Request ceilings and rate limits are not
/// part of these endpoints, so requests are a plain count, never a percentage.
public struct OpenAIAPIProvider: UsageProvider {
    public let descriptor = ProviderDescriptor.of(.openAIAPI)
    let credentials: CredentialSource
    let client: HTTPClient
    let baseURL: URL

    public init(credentials: CredentialSource, client: HTTPClient = URLSession.shared,
                baseURL: URL = URL(string: "https://api.openai.com")!) {
        self.credentials = credentials
        self.client = client
        self.baseURL = baseURL
    }

    struct Page<Item: Decodable>: Decodable {
        struct Bucket: Decodable {
            let start_time: Int
            let end_time: Int
            let results: [Item]
        }
        let data: [Bucket]
        let has_more: Bool
        let next_page: String?
    }

    struct CostItem: Decodable {
        struct Amount: Decodable {
            /// Numeric value in the currency's main unit (dollars for "usd").
            let value: Double
            let currency: String
        }
        let amount: Amount
    }

    struct CompletionsItem: Decodable {
        let input_tokens: Int
        let output_tokens: Int
        let num_model_requests: Int
    }

    public func fetchUsage(now: Date) async throws -> ProviderSnapshot {
        guard let key = credentials.secret(for: .openAIAPI), !key.isEmpty else { throw ProviderError.missingCredentials }

        var spend = Decimal(0)
        var currency = "USD"
        var page: String?
        repeat {
            var query = [URLQueryItem(name: "start_time", value: String(Int(HTTP.monthStart(now).timeIntervalSince1970))),
                         URLQueryItem(name: "bucket_width", value: "1d"),
                         URLQueryItem(name: "limit", value: "31")]
            if let page { query.append(URLQueryItem(name: "page", value: page)) }
            let result = try await HTTP.get(Page<CostItem>.self, request("/v1/organization/costs", query, key: key), client: client)
            for item in result.data.flatMap(\.results) {
                // Decimal(string:) avoids binary floating-point drift when summing.
                spend += Decimal(string: String(item.amount.value)) ?? 0
                currency = item.amount.currency.uppercased()
            }
            page = result.has_more ? result.next_page : nil
        } while page != nil

        let usage = try await HTTP.get(Page<CompletionsItem>.self, request("/v1/organization/usage/completions", [
            URLQueryItem(name: "start_time", value: String(Int(HTTP.dayStart(now).timeIntervalSince1970))),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: "1"),
        ], key: key), client: client)
        let results = usage.data.flatMap(\.results)
        let requests = results.reduce(0) { $0 + $1.num_model_requests }
        let tokens = results.reduce(0) { $0 + $1.input_tokens + $1.output_tokens }

        return ProviderSnapshot(provider: .openAIAPI, plan: "API · admin key", metrics: [
            UsageMetric(id: "spend", label: "API spend · \(HTTP.monthName(now))", value: .spend(Money(spend, currencyCode: currency)),
                        note: "Month to date (UTC)"),
            UsageMetric(id: "requests", label: "Requests today (UTC)", value: .tally(count: requests, noun: "requests"),
                        note: "Completions endpoints"),
            UsageMetric(id: "tokens", label: "Tokens today (UTC)", value: .tally(count: tokens, noun: "tokens")),
            UsageMetric(id: "tpm", label: "Tokens per minute", value: .unknown, note: "Not reported by this provider"),
        ], fetchedAt: now, isDemo: false)
    }

    func request(_ path: String, _ query: [URLQueryItem], key: String) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        var r = URLRequest(url: components.url!)
        r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        r.setValue(HTTP.userAgent, forHTTPHeaderField: "User-Agent")
        r.timeoutInterval = 20
        return r
    }
}
