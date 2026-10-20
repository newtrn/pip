import Foundation

/// The one network call providers need, so tests can substitute canned responses.
public protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPClient {}

/// Where an API provider finds its key.
public protocol CredentialSource: Sendable {
    func secret(for provider: ProviderID) -> String?
}

extension KeychainStore: CredentialSource {
    public func secret(for provider: ProviderID) -> String? { read(provider.rawValue) }
}

enum HTTP {
    static let userAgent = "Pip/0.1 (macOS menu bar usage monitor)"

    /// Performs a GET and maps auth and transport failures to `ProviderError`.
    static func get<T: Decodable>(_ type: T.Type, _ request: URLRequest, client: HTTPClient, decoder: JSONDecoder = JSONDecoder()) async throws -> T {
        let data: Data, response: URLResponse
        do {
            (data, response) = try await client.data(for: request)
        } catch {
            throw ProviderError.network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300: break
        case 401, 403: throw ProviderError.unauthorized
        case 429: throw ProviderError.network("Rate limited, will retry")
        default: throw ProviderError.network("HTTP \(status)")
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw ProviderError.network("Unexpected response format")
        }
    }

    static func monthStart(_ now: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
    }

    static func dayStart(_ now: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.startOfDay(for: now)
    }

    static func monthName(_ now: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "LLLL"
        return f.string(from: now)
    }
}
