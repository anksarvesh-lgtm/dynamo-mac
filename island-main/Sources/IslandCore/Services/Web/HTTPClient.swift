import Foundation

/// Small HTTP helper shared by web search, page fetching and AI providers.
/// Every call has a timeout, honours task cancellation, retries transient failures with backoff,
/// and maps 429 to `SearchError.rateLimited`.
public struct HTTPClient: Sendable {
    public var session: URLSession
    public var timeout: TimeInterval
    public var retries: Int
    public static let userAgent = "Island/1.0 (+https://github.com/poshak2004/island)"

    public init(session: URLSession = .shared, timeout: TimeInterval = 8, retries: Int = 1) {
        self.session = session
        self.timeout = timeout
        self.retries = retries
    }

    public func data(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var req = request
        req.timeoutInterval = timeout
        if req.value(forHTTPHeaderField: "User-Agent") == nil { req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent") }
        var attempt = 0
        while true {
            try Task.checkCancellation()
            do {
                let (data, response) = try await session.data(for: req)
                guard let http = response as? HTTPURLResponse else { throw SearchError.invalidResponse }
                if http.statusCode == 429 {
                    let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                    throw SearchError.rateLimited(retryAfter: retryAfter)
                }
                if (500...599).contains(http.statusCode), attempt < retries {
                    attempt += 1
                    try await Task.sleep(nanoseconds: UInt64(0.4 * Double(attempt) * 1_000_000_000))
                    continue
                }
                return (data, http)
            } catch let e as URLError where attempt < retries && [.timedOut, .networkConnectionLost].contains(e.code) {
                attempt += 1
                try await Task.sleep(nanoseconds: UInt64(0.4 * Double(attempt) * 1_000_000_000))
            }
        }
    }

    public func json(_ url: URL, headers: [String: String] = [:]) async throws -> Any {
        var req = URLRequest(url: url)
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        let (data, http) = try await data(req)
        guard (200...299).contains(http.statusCode) else { throw SearchError.network("HTTP \(http.statusCode)") }
        do { return try JSONSerialization.jsonObject(with: data) } catch { throw SearchError.invalidResponse }
    }
}
