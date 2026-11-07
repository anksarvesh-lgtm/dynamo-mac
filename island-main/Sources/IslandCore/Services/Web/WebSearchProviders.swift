import Foundation

/// Web search providers. Each returns only what the API actually returned — results are never synthesised.
public enum WebSearchProviderID: String, CaseIterable, Sendable { case wikipedia, duckduckgo, brave }

public struct WikipediaSearchProvider: SearchProvider {
    public let id = "wikipedia"
    public let category = SearchCategory.web
    public let timeout: TimeInterval = 5
    let http: HTTPClient
    let language: String

    public init(http: HTTPClient = HTTPClient(timeout: 5), language: String = Locale.current.language.languageCode?.identifier ?? "en") {
        self.http = http
        self.language = language.count == 2 ? language : "en"
    }

    public func search(_ request: SearchRequest) async throws -> [SearchResult] {
        var c = URLComponents(string: "https://\(language).wikipedia.org/w/api.php")!
        c.queryItems = [.init(name: "action", value: "query"), .init(name: "list", value: "search"), .init(name: "format", value: "json"),
                        .init(name: "srsearch", value: request.query), .init(name: "srlimit", value: String(request.limit)),
                        .init(name: "srprop", value: "snippet|timestamp")]
        let json = try await http.json(c.url!)
        return Self.parse(json, language: language)
    }

    static func parse(_ json: Any, language: String) -> [SearchResult] {
        guard let q = (json as? [String: Any])?["query"] as? [String: Any], let items = q["search"] as? [[String: Any]] else { return [] }
        let iso = ISO8601DateFormatter()
        return items.enumerated().compactMap { i, item in
            guard let title = item["title"] as? String,
                  let url = URL(string: "https://\(language).wikipedia.org/wiki/" + (title.replacingOccurrences(of: " ", with: "_").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")) else { return nil }
            return SearchResult(id: "wiki-\(title)", category: .web, providerID: "wikipedia", title: title,
                                snippet: (item["snippet"] as? String).map(HTMLTextExtractor.plain), url: url, symbol: "book",
                                faviconURL: URL(string: "https://\(language).wikipedia.org/static/favicon/wikipedia.ico"),
                                timestamp: (item["timestamp"] as? String).flatMap(iso.date(from:)), score: 0.5 - Double(i) * 0.01,
                                command: .openURL(url))
        }
    }
}

/// DuckDuckGo Instant Answer API: free and keyless, returns abstracts and related topics (not full web results).
public struct DuckDuckGoProvider: SearchProvider {
    public let id = "duckduckgo"
    public let category = SearchCategory.web
    public let timeout: TimeInterval = 5
    let http: HTTPClient

    public init(http: HTTPClient = HTTPClient(timeout: 5)) { self.http = http }

    public func search(_ request: SearchRequest) async throws -> [SearchResult] {
        var c = URLComponents(string: "https://api.duckduckgo.com/")!
        c.queryItems = [.init(name: "q", value: request.query), .init(name: "format", value: "json"),
                        .init(name: "no_html", value: "1"), .init(name: "skip_disambig", value: "1")]
        return Self.parse(try await http.json(c.url!), limit: request.limit)
    }

    static func parse(_ json: Any, limit: Int) -> [SearchResult] {
        guard let obj = json as? [String: Any] else { return [] }
        var out: [SearchResult] = []
        if let abstract = obj["AbstractText"] as? String, !abstract.isEmpty,
           let url = (obj["AbstractURL"] as? String).flatMap(URL.init(string:)) {
            out.append(SearchResult(id: "ddg-abstract-\(url.absoluteString)", category: .web, providerID: "duckduckgo",
                                    title: (obj["Heading"] as? String) ?? url.host ?? "Result", snippet: abstract, url: url,
                                    symbol: "text.book.closed", score: 0.7, command: .openURL(url)))
        }
        func topics(_ arr: [[String: Any]]) -> [[String: Any]] {
            arr.flatMap { ($0["Topics"] as? [[String: Any]]).map(topics) ?? [$0] }
        }
        for t in topics(obj["RelatedTopics"] as? [[String: Any]] ?? []) {
            guard out.count < limit, let text = t["Text"] as? String, let url = (t["FirstURL"] as? String).flatMap(URL.init(string:)) else { continue }
            let title = text.components(separatedBy: " - ").first ?? text
            out.append(SearchResult(id: "ddg-\(url.absoluteString)", category: .web, providerID: "duckduckgo", title: title,
                                    snippet: text, url: url, symbol: "globe", score: 0.4 - Double(out.count) * 0.01, command: .openURL(url)))
        }
        return out
    }
}

/// Brave Search API (requires the user's own API key from the Keychain).
public struct BraveSearchProvider: SearchProvider {
    public let id = "brave"
    public let category = SearchCategory.web
    public let timeout: TimeInterval = 6
    let http: HTTPClient
    let apiKey: @Sendable () -> String?

    public init(http: HTTPClient = HTTPClient(timeout: 6), apiKey: @escaping @Sendable () -> String?) {
        self.http = http
        self.apiKey = apiKey
    }

    public func search(_ request: SearchRequest) async throws -> [SearchResult] {
        guard let key = apiKey(), !key.isEmpty else { throw SearchError.unavailable("Add a Brave Search API key in Settings") }
        var c = URLComponents(string: "https://api.search.brave.com/res/v1/web/search")!
        c.queryItems = [.init(name: "q", value: request.query), .init(name: "count", value: String(request.limit))]
        let json = try await http.json(c.url!, headers: ["X-Subscription-Token": key, "Accept": "application/json"])
        return Self.parse(json)
    }

    static func parse(_ json: Any) -> [SearchResult] {
        guard let web = (json as? [String: Any])?["web"] as? [String: Any], let items = web["results"] as? [[String: Any]] else { return [] }
        return items.enumerated().compactMap { i, r in
            guard let title = r["title"] as? String, let url = (r["url"] as? String).flatMap(URL.init(string:)) else { return nil }
            let favicon = ((r["meta_url"] as? [String: Any])?["favicon"] as? String).flatMap(URL.init(string:))
            return SearchResult(id: "brave-\(url.absoluteString)", category: .web, providerID: "brave", title: HTMLTextExtractor.plain(title),
                                snippet: (r["description"] as? String).map(HTMLTextExtractor.plain), url: url, symbol: "globe",
                                faviconURL: favicon, score: 0.8 - Double(i) * 0.01, command: .openURL(url))
        }
    }
}

/// Fetches a page and extracts readable text. Only http(s), size-capped.
public struct PageFetcher: Sendable {
    let http: HTTPClient
    public init(http: HTTPClient = HTTPClient(timeout: 7, retries: 0)) { self.http = http }

    public struct Page: Sendable, Equatable {
        public var url: URL
        public var title: String
        public var text: String
    }

    public func fetch(_ url: URL) async throws -> Page {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { throw SearchError.unavailable("Unsupported URL") }
        var req = URLRequest(url: url)
        req.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let (data, http) = try await http.data(req)
        guard (200...299).contains(http.statusCode) else { throw SearchError.network("HTTP \(http.statusCode)") }
        let html = String(decoding: data.prefix(2_000_000), as: UTF8.self)
        return Page(url: url, title: HTMLTextExtractor.title(html) ?? url.host ?? url.absoluteString, text: HTMLTextExtractor.text(html))
    }
}
