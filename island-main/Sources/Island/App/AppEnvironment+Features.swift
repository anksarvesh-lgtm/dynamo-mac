import AppKit
import IslandCore

/// Secondary features layered on the core: settings/debug windows, global shortcut, search,
/// research, typed actions and automation. Kept separate from the core wiring in AppEnvironment.
@MainActor
final class FeatureHub {
    unowned let env: AppEnvironment
    let settingsWindow = SettingsWindowController()
    let debug = DebugWindows()
    let apps = ApplicationSearchProvider()
    private(set) var hotKey: HotKey?
    private var automationState: [UUID: Bool] = [:]
    var rules: [AutomationRule] = AutomationStore.load() { didSet { AutomationStore.save(rules) } }

    init(env: AppEnvironment) {
        self.env = env
    }

    func start() {
        env.commands.openSettings = { [weak self] in self.map { $0.settingsWindow.show(env: $0.env) } }
        env.commands.action = { [weak self] action, origin in self?.run(action, origin: origin) }
        hotKey = HotKey { [weak self] in self?.env.commands.perform(.ui(.toggleSearch)) }
        env.bus.subscribe { [weak self] event in self?.automate(event) }
        configure()
    }

    /// Re-applied whenever settings change.
    func configure() {
        let s = env.settings
        hotKey?.register(s.searchEnabled && s.islandEnabled ? s.searchShortcut : nil)
        debug.setOverlay(s.performanceOverlay, env: env)

        var providers: [any SearchProvider] = [ActionSearchProvider(webSearchURL: Self.browserSearchURL), apps]
        if s.fileSearchEnabled { providers.append(FileSearchProvider()) }
        if s.webSearchEnabled {
            if s.webSearchProviders.contains("wikipedia") { providers.append(WikipediaSearchProvider()) }
            if s.webSearchProviders.contains("duckduckgo") { providers.append(DuckDuckGoProvider()) }
            if s.webSearchProviders.contains("brave") { providers.append(BraveSearchProvider(apiKey: { Keychain.get(account: "brave-search") })) }
        }
        env.search.engine = SearchEngine(providers: providers)

        let kind = s.aiProvider
        if let ai = AIProviderFactory.make(kind: kind, model: s.aiModel, apiKey: { Keychain.get(account: kind.rawValue) }) {
            let webProviders = providers.filter { $0.category == .web }
            let research = ResearchEngine(ai: ai, search: { q in await Self.collectWeb(q, providers: webProviders) })
            env.search.research = { q in try await research.answer(q) }
        } else {
            env.search.research = nil
        }
    }

    nonisolated static func browserSearchURL(_ q: String) -> URL? {
        var c = URLComponents(string: "https://duckduckgo.com/")!
        c.queryItems = [.init(name: "q", value: q)]
        return c.url
    }

    nonisolated static func collectWeb(_ q: String, providers: [any SearchProvider]) async -> [SearchResult] {
        let engine = SearchEngine(providers: providers)
        var out: [SearchResult] = []
        for await outcome in engine.search("web \(q)", limit: 6) {
            if case .success(let r) = outcome.result { out += r }
        }
        return out.sorted { $0.score > $1.score }
    }

    // MARK: Actions

    func run(_ action: AppAction, origin: ActionOrigin) {
        guard PermissionPolicy.isAllowed(action.safety, origin: origin, userConfirmed: origin == .user) else { return }
        switch action {
        case .startTimer(let d, let label): env.commands.perform(.timer(.start(duration: d, label: label)), origin: origin)
        case .media(let verb):
            switch verb {
            case .play: env.media.playDefault()
            case .pause: env.media.perform(.pause, source: nil)
            case .toggle: env.media.perform(.togglePlayPause, source: nil)
            case .next: env.media.perform(.next, source: nil)
            case .previous: env.media.perform(.previous, source: nil)
            }
        case .webSearch(let q):
            env.island.toggleSearchIfNeeded()
            env.search.query = "web \(q)"
        case .findFile(let q):
            env.island.toggleSearchIfNeeded()
            env.search.query = "file \(q)"
        case .openApplication(let name):
            if let url = apps.find(name) { env.commands.perform(.launchApplication(url), origin: origin) }
        case .openURL(let url): env.commands.perform(.openURL(url), origin: origin)
        }
    }

    // MARK: Automation

    private func automate(_ event: IslandEvent) {
        let ctx = AutomationContext(activeKinds: Set(env.manager.ordered.map(\.kind)))
        for action in AutomationEngine.evaluate(rules, event: event, context: ctx, state: &automationState) {
            switch action {
            case .presentIsland(let s): env.commands.perform(.ui(.presentTransient(seconds: s)), origin: .automation)
            case .playSound(let name): NSSound(named: NSSound.Name(name))?.play()
            case .showEvent(let symbol, let title):
                env.manager.submit(.upsert(Activity(id: "automation.\(UUID().uuidString)", kind: .notification, priority: .normal,
                                                    content: .event(SystemEventActivity(symbol: symbol, title: title)),
                                                    expiresAt: Date().addingTimeInterval(4))))
            }
        }
    }
}

extension IslandViewModel {
    func toggleSearchIfNeeded() { if mode != .search { toggleSearch() } }
}
