import Foundation

public enum SearchCategory: String, Sendable, CaseIterable, Codable {
    case action, application, file, web, ai

    public var title: String {
        switch self {
        case .action: "Actions"
        case .application: "Applications"
        case .file: "Files"
        case .web: "Web"
        case .ai: "Ask"
        }
    }
    /// Section order in the Island.
    public var order: Int {
        switch self {
        case .action: 0
        case .application: 1
        case .file: 2
        case .web: 3
        case .ai: 4
        }
    }
}

public struct SearchRequest: Sendable, Equatable {
    public let id: UUID
    public let query: String
    public let limit: Int
    public init(query: String, limit: Int = 6, id: UUID = UUID()) {
        self.id = id
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.limit = max(1, limit)
    }
}

public struct SearchResult: Identifiable, Sendable, Equatable {
    public let id: String
    public var category: SearchCategory
    public var providerID: String
    public var title: String
    public var subtitle: String?
    public var snippet: String?
    public var url: URL?
    public var domain: String?
    /// SF Symbol, used when there's no file/app icon.
    public var symbol: String?
    /// File or app bundle to draw the Finder icon for.
    public var iconFileURL: URL?
    public var faviconURL: URL?
    public var timestamp: Date?
    public var score: Double
    public var command: IslandCommand?

    public init(id: String, category: SearchCategory, providerID: String, title: String, subtitle: String? = nil,
                snippet: String? = nil, url: URL? = nil, domain: String? = nil, symbol: String? = nil,
                iconFileURL: URL? = nil, faviconURL: URL? = nil, timestamp: Date? = nil, score: Double = 0,
                command: IslandCommand? = nil) {
        self.id = id
        self.category = category
        self.providerID = providerID
        self.title = title
        self.subtitle = subtitle
        self.snippet = snippet
        self.url = url
        self.domain = domain ?? url?.host?.replacingOccurrences(of: "www.", with: "")
        self.symbol = symbol
        self.iconFileURL = iconFileURL
        self.faviconURL = faviconURL
        self.timestamp = timestamp
        self.score = score
        self.command = command
    }
}

public enum SearchError: Error, Equatable, Sendable, CustomStringConvertible {
    case timeout
    case cancelled
    case rateLimited(retryAfter: TimeInterval?)
    case network(String)
    case invalidResponse
    case unavailable(String)

    public var description: String {
        switch self {
        case .timeout: "Timed out"
        case .cancelled: "Cancelled"
        case .rateLimited: "Rate limited — try again shortly"
        case .network(let m): m
        case .invalidResponse: "Unexpected response"
        case .unavailable(let m): m
        }
    }

    public static func from(_ error: Error) -> SearchError {
        if let e = error as? SearchError { return e }
        if error is CancellationError { return .cancelled }
        if let u = error as? URLError {
            switch u.code {
            case .cancelled: return .cancelled
            case .timedOut: return .timeout
            case .notConnectedToInternet, .networkConnectionLost: return .network("You're offline")
            default: return .network(u.localizedDescription)
            }
        }
        return .network(error.localizedDescription)
    }
}

public protocol SearchProvider: Sendable {
    var id: String { get }
    var category: SearchCategory { get }
    var timeout: TimeInterval { get }
    func search(_ request: SearchRequest) async throws -> [SearchResult]
}

public struct ProviderOutcome: Sendable {
    public let providerID: String
    public let category: SearchCategory
    public let result: Result<[SearchResult], SearchError>
}
