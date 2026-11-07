import AppKit
import IslandCore

/// Installed applications (scanned once per search session, cached in memory).
final class ApplicationSearchProvider: SearchProvider, @unchecked Sendable {
    let id = "applications"
    let category = SearchCategory.application
    let timeout: TimeInterval = 1.5
    private let lock = NSLock()
    private var cache: [(name: String, url: URL)]?
    private var cachedAt = Date.distantPast

    func search(_ request: SearchRequest) async throws -> [SearchResult] {
        let apps = loadApps()
        return apps.compactMap { app -> SearchResult? in
            let s = SearchRanker.score(app.name, query: request.query)
            guard s > 0.3 else { return nil }
            return SearchResult(id: "app-\(app.url.path)", category: .application, providerID: id, title: app.name,
                                subtitle: app.url.deletingLastPathComponent().path, iconFileURL: app.url, score: s,
                                command: .launchApplication(app.url))
        }
        .sorted { $0.score > $1.score }
    }

    func loadApps() -> [(name: String, url: URL)] {
        lock.lock(); defer { lock.unlock() }
        if let cache, Date().timeIntervalSince(cachedAt) < 300 { return cache }
        let fm = FileManager.default
        let dirs = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                    NSHomeDirectory() + "/Applications"]
        var out: [(String, URL)] = []
        var seen = Set<String>()
        for d in dirs {
            guard let items = try? fm.contentsOfDirectory(atPath: d) else { continue }
            for i in items where i.hasSuffix(".app") {
                let name = String(i.dropLast(4))
                if seen.insert(name).inserted { out.append((name, URL(fileURLWithPath: d).appendingPathComponent(i))) }
            }
        }
        cache = out
        cachedAt = Date()
        return out
    }

    /// Best match for "open <name>".
    func find(_ name: String) -> URL? {
        loadApps().map { ($0.url, SearchRanker.score($0.name, query: name)) }.filter { $0.1 >= 0.6 }.max { $0.1 < $1.1 }?.0
    }
}

/// Files via Spotlight (NSMetadataQuery — the public Spotlight API). Name matches only, capped.
struct FileSearchProvider: SearchProvider {
    let id = "files"
    let category = SearchCategory.file
    let timeout: TimeInterval = 2.5

    func search(_ request: SearchRequest) async throws -> [SearchResult] {
        guard request.query.count >= 2 else { return [] }
        let q = request.query
        let limit = request.limit
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[SearchResult], Error>) in
                DispatchQueue.main.async {
                    FileQuery.run(q, limit: limit) { cont.resume(returning: $0) }
                }
            }
        } onCancel: {}
    }
}

@MainActor
private final class FileQuery {
    private static var active: Set<ObjectIdentifier> = []
    private static var holders: [ObjectIdentifier: FileQuery] = [:]
    let query = NSMetadataQuery()
    var observer: NSObjectProtocol?

    static func run(_ text: String, limit: Int, completion: @escaping ([SearchResult]) -> Void) {
        let fq = FileQuery()
        let key = ObjectIdentifier(fq)
        holders[key] = fq
        let escaped = text.replacingOccurrences(of: "\"", with: "")
        fq.query.predicate = NSPredicate(fromMetadataQueryString: "kMDItemDisplayName == \"*\(escaped)*\"cd && kMDItemContentTypeTree != \"com.apple.application-bundle\"")
        fq.query.searchScopes = [NSMetadataQueryUserHomeScope]
        fq.query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]
        var finished = false
        let finish: () -> Void = {
            guard !finished else { return }
            finished = true
            fq.query.stop()
            var out: [SearchResult] = []
            for i in 0..<min(fq.query.resultCount, limit * 3) {
                guard let item = fq.query.result(at: i) as? NSMetadataItem,
                      let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
                let url = URL(fileURLWithPath: path)
                let name = url.lastPathComponent
                out.append(SearchResult(id: "file-\(path)", category: .file, providerID: "files", title: name,
                                        subtitle: (path as NSString).abbreviatingWithTildeInPath, iconFileURL: url,
                                        timestamp: item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date,
                                        score: SearchRanker.score(name, query: text) * 0.9, command: .openFile(url)))
            }
            if let o = fq.observer { NotificationCenter.default.removeObserver(o) }
            holders[key] = nil
            completion(Array(out.sorted { $0.score > $1.score }.prefix(limit)))
        }
        fq.observer = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: fq.query, queue: .main) { _ in
            MainActor.assumeIsolated { finish() }
        }
        fq.query.start()
        // Return partial results rather than wait on a slow index.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { finish() }
    }
}

/// Typed actions parsed from the query ("timer 10 min", "open Safari", "search web for …").
struct ActionSearchProvider: SearchProvider {
    let id = "actions"
    let category = SearchCategory.action
    let timeout: TimeInterval = 0.5
    let webSearchURL: @Sendable (String) -> URL?

    func search(_ request: SearchRequest) async throws -> [SearchResult] {
        var results = ActionRouter.parse(request.query).enumerated().map { i, a in
            SearchResult(id: "action-\(i)-\(a.title)", category: .action, providerID: id, title: a.title, symbol: a.symbol,
                         score: 1 - Double(i) * 0.01, command: .action(a))
        }
        if let url = webSearchURL(request.query) {
            results.append(SearchResult(id: "action-web-browser", category: .action, providerID: id,
                                        title: "Search the web for “\(request.query)”", subtitle: "Opens your browser",
                                        symbol: "safari", score: 0.2, command: .openURL(url)))
        }
        return results
    }
}
