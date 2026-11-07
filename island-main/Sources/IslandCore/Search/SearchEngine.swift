import Foundation

/// Decides which providers a query should reach.
public enum SearchRouter {
    public enum Scope: Equatable, Sendable { case all, only(SearchCategory) }

    public struct Routed: Equatable, Sendable {
        public var query: String
        public var scope: Scope
    }

    /// `web foo` / `g foo` → web only, `file foo` / `f foo` → files, `app foo` → apps, `ask foo` / `? foo` → AI.
    public static func route(_ raw: String) -> Routed {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = q.lowercased()
        let prefixes: [(String, SearchCategory)] = [
            ("web ", .web), ("g ", .web), ("file ", .file), ("files ", .file), ("f ", .file),
            ("app ", .application), ("ask ", .ai), ("? ", .ai), ("?", .ai),
        ]
        for (p, c) in prefixes where lower.hasPrefix(p) {
            let rest = String(q.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { return Routed(query: rest, scope: .only(c)) }
        }
        return Routed(query: q, scope: .all)
    }

    public static func providers(for routed: Routed, from all: [any SearchProvider]) -> [any SearchProvider] {
        switch routed.scope {
        case .all: all.filter { $0.category != .ai }
        case .only(let c): all.filter { $0.category == c }
        }
    }
}

/// Runs providers concurrently. Each provider is isolated: it has its own timeout, failures are
/// reported per provider, and cancelling the consuming task cancels every in-flight provider.
public struct SearchEngine: Sendable {
    public let providers: [any SearchProvider]

    public init(providers: [any SearchProvider]) { self.providers = providers }

    public func search(_ raw: String, limit: Int = 6) -> AsyncStream<ProviderOutcome> {
        let routed = SearchRouter.route(raw)
        let selected = SearchRouter.providers(for: routed, from: providers)
        let request = SearchRequest(query: routed.query, limit: limit)
        return AsyncStream { continuation in
            let task = Task {
                guard !request.query.isEmpty else { continuation.finish(); return }
                await withTaskGroup(of: ProviderOutcome.self) { group in
                    for provider in selected {
                        group.addTask {
                            do {
                                let results = try await withTimeout(provider.timeout) { try await provider.search(request) }
                                return ProviderOutcome(providerID: provider.id, category: provider.category,
                                                       result: .success(Array(results.prefix(request.limit))))
                            } catch {
                                return ProviderOutcome(providerID: provider.id, category: provider.category,
                                                       result: .failure(SearchError.from(error)))
                            }
                        }
                    }
                    for await outcome in group {
                        if Task.isCancelled { break }
                        continuation.yield(outcome)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Runs `operation`, throwing `SearchError.timeout` if it doesn't finish in time.
public func withTimeout<T: Sendable>(_ seconds: TimeInterval, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(max(0.01, seconds) * 1_000_000_000))
            throw SearchError.timeout
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else { throw SearchError.cancelled }
        return first
    }
}

/// Simple relevance scoring shared by local providers.
public enum SearchRanker {
    public static func score(_ candidate: String, query: String) -> Double {
        let c = candidate.lowercased(), q = query.lowercased()
        guard !q.isEmpty else { return 0 }
        if c == q { return 1.0 }
        if c.hasPrefix(q) { return 0.9 - min(0.2, Double(c.count - q.count) * 0.005) }
        let words = c.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.contains(where: { $0.hasPrefix(q) }) { return 0.75 }
        let initials = String(words.compactMap(\.first))
        if initials.hasPrefix(q) { return 0.7 }
        if c.contains(q) { return 0.6 }
        // Ordered subsequence (fuzzy).
        var it = c.makeIterator()
        var matched = 0
        for ch in q {
            while let n = it.next() { if n == ch { matched += 1; break } }
        }
        return matched == q.count ? 0.35 : 0
    }
}
