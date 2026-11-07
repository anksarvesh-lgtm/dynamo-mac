import Foundation

/// question → (search?) → fetch → extract → dedupe → summarise → cite.
/// Citations are validated against the sources actually fetched; any `[n]` the model invents is removed.
public struct ResearchEngine: Sendable {
    public struct Source: Sendable, Equatable {
        public var index: Int
        public var title: String
        public var url: URL
        public var text: String
    }

    let ai: AIProvider
    let search: @Sendable (String) async -> [SearchResult]
    let fetcher: PageFetcher
    let maxSources: Int

    public init(ai: AIProvider, search: @escaping @Sendable (String) async -> [SearchResult], fetcher: PageFetcher = PageFetcher(), maxSources: Int = 4) {
        self.ai = ai
        self.search = search
        self.fetcher = fetcher
        self.maxSources = maxSources
    }

    /// Cheap heuristic: personal/creative/definitional-math questions don't need the web.
    public static func needsWebSearch(_ q: String) -> Bool {
        let l = q.lowercased()
        let offline = ["rewrite", "translate", "summarize this", "write a", "poem", "joke", "explain like", "what is 2", "calculate", "convert "]
        if offline.contains(where: l.contains) { return false }
        let fresh = ["latest", "today", "news", "current", "price", "2025", "2026", "who is", "when is", "release", "weather", "score", "best"]
        return fresh.contains(where: l.contains) || q.split(separator: " ").count >= 3
    }

    public func answer(_ question: String) async throws -> ResearchAnswer {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { throw AIError.emptyResponse }
        var sources: [Source] = []
        if Self.needsWebSearch(q) {
            let results = Self.dedupe(await search(q)).prefix(maxSources * 2)
            let pages = await withTaskGroup(of: (Int, PageFetcher.Page?).self) { group in
                for (i, r) in results.enumerated() {
                    guard let url = r.url else { continue }
                    group.addTask { (i, try? await withTimeout(8) { try await fetcher.fetch(url) }) }
                }
                var out: [(Int, PageFetcher.Page)] = []
                for await (i, p) in group { if let p, p.text.count > 200 { out.append((i, p)) } }
                return out.sorted { $0.0 < $1.0 }.map(\.1)
            }
            var seenText = Set<String>()
            for p in pages where sources.count < maxSources {
                let fp = String(p.text.prefix(300))
                guard seenText.insert(fp).inserted else { continue }
                sources.append(Source(index: sources.count + 1, title: p.title, url: p.url, text: String(p.text.prefix(3500))))
            }
            // Fall back to search snippets if pages couldn't be fetched (they're still real retrieved text).
            if sources.isEmpty {
                for r in results where sources.count < maxSources {
                    guard let url = r.url, let snippet = r.snippet, !snippet.isEmpty else { continue }
                    sources.append(Source(index: sources.count + 1, title: r.title, url: url, text: snippet))
                }
            }
        }
        let raw = try await ai.complete(system: Self.systemPrompt(hasSources: !sources.isEmpty),
                                        messages: [AIMessage(role: .user, text: Self.prompt(question: q, sources: sources))], maxTokens: 1200)
        return Self.finalize(raw, sources: sources)
    }

    static func systemPrompt(hasSources: Bool) -> String {
        if hasSources {
            return """
            You answer questions inside a small macOS overlay. Use only the numbered sources provided. \
            Cite claims with [n] matching a source number. If the sources don't answer the question, say so plainly. \
            Keep the answer under 120 words, plain text, no markdown headings.
            """
        }
        return "You answer questions inside a small macOS overlay. Keep the answer under 120 words, plain text. Do not cite sources or URLs."
    }

    static func prompt(question: String, sources: [Source]) -> String {
        guard !sources.isEmpty else { return question }
        let body = sources.map { "[\($0.index)] \($0.title) — \($0.url.absoluteString)\n\($0.text)" }.joined(separator: "\n\n")
        return "Sources:\n\n\(body)\n\nQuestion: \(question)"
    }

    /// Removes citation markers that don't refer to a real source and returns only the sources cited.
    public static func finalize(_ raw: String, sources: [Source]) -> ResearchAnswer {
        let valid = Set(sources.map(\.index))
        var cited: [Int] = []
        let regex = try! NSRegularExpression(pattern: "\\[(\\d{1,2})\\]")
        let ns = raw as NSString
        var text = raw
        for m in regex.matches(in: raw, range: NSRange(location: 0, length: ns.length)).reversed() {
            let n = Int(ns.substring(with: m.range(at: 1))) ?? -1
            if valid.contains(n) {
                if !cited.contains(n) { cited.append(n) }
            } else if let r = Range(m.range, in: text) {
                text.removeSubrange(r)
            }
        }
        let citations = sources.filter { cited.contains($0.index) }.map { Citation(index: $0.index, title: $0.title, url: $0.url) }
        return ResearchAnswer(text: text.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines),
                              citations: citations, usedWeb: !sources.isEmpty)
    }

    /// One result per URL (ignoring fragments/tracking) and at most two per domain.
    public static func dedupe(_ results: [SearchResult]) -> [SearchResult] {
        var seen = Set<String>(), perDomain: [String: Int] = [:], out: [SearchResult] = []
        for r in results {
            guard let url = r.url, var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { continue }
            c.fragment = nil
            c.queryItems = c.queryItems?.filter { !$0.name.hasPrefix("utm_") }
            if c.queryItems?.isEmpty == true { c.queryItems = nil }
            let key = (c.host?.replacingOccurrences(of: "www.", with: "") ?? "") + c.path.lowercased() + (c.query ?? "")
            let domain = c.host?.replacingOccurrences(of: "www.", with: "") ?? ""
            guard seen.insert(key).inserted, perDomain[domain, default: 0] < 2 else { continue }
            perDomain[domain, default: 0] += 1
            out.append(r)
        }
        return out
    }
}
