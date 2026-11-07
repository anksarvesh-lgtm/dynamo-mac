import AppKit
import Combine

struct QuickAction: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let keywords: [String]
    let run: () -> Void
}

struct LauncherItem: Identifiable {
    enum Kind {
        case app(AppEntry)
        case calc(String)
        case convert(String)
        case file(URL)
        case action(QuickAction)
    }
    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    let image: NSImage?
    let symbol: String?
}

/// Fuzzy app search with recent/frequent ranking, plus calculator, unit conversion, file search
/// (Spotlight) and quick actions.
final class LauncherEngine: ObservableObject {
    @Published private(set) var fileResults: [LauncherItem] = []
    var actions: [QuickAction] = []

    private var metadataQuery: NSMetadataQuery?
    private var fileWork: DispatchWorkItem?
    private var queryObserver: Any?
    private static let countsKey = "launchCounts"
    private static let recentsKey = "recentLaunches"

    // MARK: Results

    func results(for raw: String, apps: [AppEntry]) -> [LauncherItem] {
        let q = raw.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return recentsAndFrequent(apps) }
        var out: [LauncherItem] = []

        if Calculator.looksLikeMath(q), let v = Calculator.evaluate(q) {
            let text = Calculator.format(v)
            out.append(LauncherItem(id: "calc", kind: .calc(text), title: text,
                                    subtitle: "= \(q)   ·   ↩ copies the result", image: nil, symbol: "equal.circle.fill"))
        }
        if let c = UnitConverter.convert(q) {
            let text = "\(Calculator.format(c.value)) \(c.toSymbol)"
            out.append(LauncherItem(id: "convert", kind: .convert(text), title: text,
                                    subtitle: "\(q)   ·   ↩ copies the result", image: nil, symbol: "arrow.left.arrow.right.circle.fill"))
        }
        if let minutes = Self.timerMinutes(in: q) {
            let a = QuickAction(id: "timer.\(minutes)", title: "Start \(minutes) minute timer", symbol: "timer", keywords: []) {
                NotificationCenter.default.post(name: .notchStartTimer, object: minutes)
            }
            out.append(actionItem(a))
        }

        let scored = apps.compactMap { app -> (AppEntry, Int)? in
            guard let s = Self.score(q, app.name) else { return nil }
            return (app, s + frequencyBonus(app))
        }
        .sorted { $0.1 > $1.1 }
        out += scored.prefix(6).map { appItem($0.0) }

        let matchingActions = actions.filter { a in
            Self.score(q, a.title) != nil || a.keywords.contains { Self.score(q, $0) != nil }
        }
        out += matchingActions.prefix(3).map(actionItem)
        out += fileResults.prefix(4)
        return Array(out.prefix(10))
    }

    private func recentsAndFrequent(_ apps: [AppEntry]) -> [LauncherItem] {
        let byPath = Dictionary(uniqueKeysWithValues: apps.map { ($0.url.path, $0) })
        var out: [LauncherItem] = []
        var seen = Set<String>()
        for path in recents where byPath[path] != nil && !seen.contains(path) {
            seen.insert(path); out.append(appItem(byPath[path]!))
        }
        let frequent = counts.sorted { $0.value > $1.value }.map(\.key)
        for path in frequent where byPath[path] != nil && !seen.contains(path) && out.count < 8 {
            seen.insert(path); out.append(appItem(byPath[path]!))
        }
        for app in apps where !seen.contains(app.url.path) && out.count < 8 {
            seen.insert(app.url.path); out.append(appItem(app))
        }
        return out
    }

    // MARK: Scoring

    /// Higher is better; nil = no match. Exact > prefix > word start > substring > subsequence.
    static func score(_ query: String, _ name: String) -> Int? {
        let q = query.lowercased(), n = name.lowercased()
        if n == q { return 1000 }
        if n.hasPrefix(q) { return 600 - n.count }
        if let r = n.range(of: q) {
            let offset = n.distance(from: n.startIndex, to: r.lowerBound)
            let atWord = offset == 0 || n[n.index(before: r.lowerBound)] == " "
            return (atWord ? 400 : 250) - offset
        }
        // Initials ("sp" → "System Preferences").
        let initials = n.split(separator: " ").compactMap { $0.first }.map(String.init).joined()
        if initials.hasPrefix(q) { return 350 }
        // Subsequence with gap penalty.
        var idx = n.startIndex
        var last: String.Index?
        var gaps = 0
        for ch in q {
            guard let found = n[idx...].firstIndex(of: ch) else { return nil }
            if let last { gaps += n.distance(from: last, to: found) - 1 }
            last = found
            idx = n.index(after: found)
        }
        return gaps > 12 ? nil : 150 - gaps * 5
    }

    private static func timerMinutes(in q: String) -> Int? {
        let pattern = try! NSRegularExpression(pattern: #"^(?:timer|t|pomodoro)\s+(\d{1,3})\s*(?:m|min|mins|minutes)?$"#,
                                               options: [.caseInsensitive])
        let ns = q as NSString
        guard let m = pattern.firstMatch(in: q, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return Int(ns.substring(with: m.range(at: 1)))
    }

    // MARK: Frequency / recents

    private var counts: [String: Int] {
        get { UserDefaults.standard.dictionary(forKey: Self.countsKey) as? [String: Int] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.countsKey) }
    }
    private var recents: [String] {
        get { UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: Self.recentsKey) }
    }
    private func frequencyBonus(_ app: AppEntry) -> Int {
        let c = counts[app.url.path] ?? 0
        return c == 0 ? 0 : Int(log2(Double(c) + 1) * 20)
    }
    func recordLaunch(_ app: AppEntry) {
        var c = counts; c[app.url.path, default: 0] += 1; counts = c
        var r = recents; r.removeAll { $0 == app.url.path }; r.insert(app.url.path, at: 0)
        recents = Array(r.prefix(8))
    }

    // MARK: Items

    private func appItem(_ app: AppEntry) -> LauncherItem {
        LauncherItem(id: "app:" + app.url.path, kind: .app(app), title: app.name,
                     subtitle: app.url.deletingLastPathComponent().path, image: app.icon, symbol: nil)
    }
    private func actionItem(_ a: QuickAction) -> LauncherItem {
        LauncherItem(id: "action:" + a.id, kind: .action(a), title: a.title, subtitle: "Quick action", image: nil, symbol: a.symbol)
    }

    // MARK: File search (Spotlight)

    func searchFiles(_ raw: String) {
        fileWork?.cancel()
        let q = raw.trimmingCharacters(in: .whitespaces)
        guard q.count >= 3, !Calculator.looksLikeMath(q), UnitConverter.convert(q) == nil else {
            stopQuery()
            if !fileResults.isEmpty { fileResults = [] }
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.runQuery(q) }
        fileWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func stopQuery() {
        if let o = queryObserver { NotificationCenter.default.removeObserver(o) }
        queryObserver = nil
        metadataQuery?.stop()
        metadataQuery = nil
    }

    private func runQuery(_ q: String) {
        stopQuery()
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemFSName CONTAINS[cd] %@ AND NOT kMDItemContentType == 'com.apple.application-bundle'", q)
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]
        queryObserver = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            query.disableUpdates()
            var items: [LauncherItem] = []
            for i in 0..<min(query.resultCount, 6) {
                guard let item = query.result(at: i) as? NSMetadataItem,
                      let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
                let url = URL(fileURLWithPath: path)
                items.append(LauncherItem(id: "file:" + path, kind: .file(url), title: url.lastPathComponent,
                                          subtitle: (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath,
                                          image: NSWorkspace.shared.icon(forFile: path), symbol: nil))
            }
            self.fileResults = items
            self.stopQuery()
        }
        metadataQuery = query
        query.start()
    }
}

extension Notification.Name {
    static let notchStartTimer = Notification.Name("NotchIsland.startTimer")
}
