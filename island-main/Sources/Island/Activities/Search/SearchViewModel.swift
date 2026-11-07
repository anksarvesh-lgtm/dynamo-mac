import AppKit
import IslandCore
import Observation

/// State for Island search mode. Results stream in per provider; a slow or failing provider never
/// blocks the others, and every keystroke cancels the previous search.
@MainActor
@Observable
final class SearchViewModel {
    struct Section: Identifiable, Equatable {
        var category: SearchCategory
        var results: [SearchResult]
        var error: String?
        var id: String { category.rawValue }
    }

    var query = "" { didSet { if query != oldValue { scheduleSearch() } } }
    private(set) var sections: [Section] = []
    private(set) var selectedID: String?
    private(set) var isSearching = false
    private(set) var focusToken = 0
    private(set) var answer: ResearchState = .idle

    @ObservationIgnored var engine: SearchEngine = SearchEngine(providers: [])
    @ObservationIgnored var commands: CommandRouter?
    @ObservationIgnored var research: ((String) async throws -> ResearchAnswer)?
    @ObservationIgnored var onHeightChange: ((CGFloat) -> Void)?
    @ObservationIgnored var compactHeight: CGFloat = 32
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var researchTask: Task<Void, Never>?

    enum ResearchState: Equatable {
        case idle
        case running(question: String)
        case done(ResearchAnswer)
        case failed(String)
    }

    var flatResults: [SearchResult] { sections.flatMap(\.results) }
    var selected: SearchResult? { flatResults.first { $0.id == selectedID } ?? flatResults.first }

    func activate() {
        focusToken += 1
        updateHeight()
    }

    func deactivate() {
        searchTask?.cancel()
        researchTask?.cancel()
        query = ""
        sections = []
        answer = .idle
        isSearching = false
        updateHeight()
    }

    func select(_ id: String) { selectedID = id }

    func execute(_ result: SearchResult? = nil) {
        guard let r = result ?? selected else { return }
        if r.category == .ai {
            ask(r.title)
            return
        }
        guard let command = r.command else { return }
        commands?.perform(command)
        if case .ui = command { return }
        commands?.perform(.ui(.collapse))
    }

    /// Arrow keys / return. Returns true when consumed.
    func handleKey(_ e: NSEvent) -> Bool {
        switch e.keyCode {
        case 125: moveSelection(1); return true   // down
        case 126: moveSelection(-1); return true  // up
        case 36, 76: execute(); return true        // return / enter
        default: return false
        }
    }

    private func moveSelection(_ delta: Int) {
        let list = flatResults
        guard !list.isEmpty else { return }
        let idx = list.firstIndex { $0.id == selected?.id } ?? 0
        selectedID = list[(idx + delta + list.count) % list.count].id
    }

    // MARK: Search

    private func scheduleSearch() {
        searchTask?.cancel()
        researchTask?.cancel()
        answer = .idle
        let q = query
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty else {
            sections = []
            isSearching = false
            updateHeight()
            return
        }
        isSearching = true
        searchTask = Task { [weak self, engine] in
            try? await Task.sleep(nanoseconds: 110_000_000)
            guard !Task.isCancelled else { return }
            var collected: [SearchCategory: Section] = [:]
            if let ai = self?.aiSuggestion(for: q) { collected[.ai] = Section(category: .ai, results: [ai]) }
            self?.publish(collected)
            for await outcome in engine.search(q) {
                guard !Task.isCancelled else { return }
                var section = collected[outcome.category] ?? Section(category: outcome.category, results: [])
                switch outcome.result {
                case .success(let results):
                    section.results = (section.results + results).sorted { $0.score > $1.score }
                case .failure(let error):
                    if error != .cancelled, section.results.isEmpty { section.error = error.description }
                }
                collected[outcome.category] = section
                self?.publish(collected)
            }
            guard !Task.isCancelled else { return }
            self?.isSearching = false
        }
    }

    private func publish(_ collected: [SearchCategory: Section]) {
        let ordered = collected.values
            .filter { !$0.results.isEmpty || $0.error != nil }
            .sorted { $0.category.order < $1.category.order }
        sections = ordered
        if selectedID == nil || !flatResults.contains(where: { $0.id == selectedID }) { selectedID = flatResults.first?.id }
        updateHeight()
    }

    private func aiSuggestion(for q: String) -> SearchResult? {
        guard research != nil else { return nil }
        let routed = SearchRouter.route(q)
        let looksLikeQuestion = routed.scope == .only(.ai) || q.hasSuffix("?")
        guard looksLikeQuestion else { return nil }
        return SearchResult(id: "ai-ask", category: .ai, providerID: "ai", title: routed.query,
                            subtitle: "Research with AI · cites sources", symbol: "sparkles", score: 1)
    }

    // MARK: Research

    func ask(_ question: String) {
        guard let research else { return }
        researchTask?.cancel()
        answer = .running(question: question)
        updateHeight()
        researchTask = Task { [weak self] in
            do {
                let result = try await research(question)
                guard !Task.isCancelled else { return }
                self?.answer = .done(result)
            } catch {
                guard !Task.isCancelled else { return }
                self?.answer = .failed((error as? LocalizedError)?.errorDescription ?? String(describing: error))
            }
            self?.updateHeight()
        }
    }

    // MARK: Layout

    var desiredHeight: CGFloat {
        var h = compactHeight + 52
        switch answer {
        case .idle: break
        case .running: return h + 70
        case .failed: return h + 80
        case .done(let a): return h + min(320, 90 + CGFloat(a.text.count) / 2.2 + CGFloat(a.citations.count) * 22)
        }
        for s in sections { h += 24 + CGFloat(max(1, s.results.count)) * 40 }
        return h + (sections.isEmpty ? 0 : 10)
    }

    private func updateHeight() { onHeightChange?(desiredHeight) }
}
