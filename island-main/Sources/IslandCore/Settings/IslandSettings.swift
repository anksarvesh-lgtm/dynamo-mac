import Foundation
import Observation

public struct IslandShortcut: Codable, Equatable, Sendable {
    /// Carbon virtual key code.
    public var keyCode: UInt32
    /// Carbon modifier mask (cmdKey, optionKey, controlKey, shiftKey).
    public var carbonModifiers: UInt32
    public var display: String

    public init(keyCode: UInt32, carbonModifiers: UInt32, display: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.display = display
    }

    /// ⌥Space
    public static let defaultSearch = IslandShortcut(keyCode: 49, carbonModifiers: 0x0800, display: "⌥Space")
}

public enum AIProviderKind: String, Codable, CaseIterable, Sendable {
    case none, anthropic, openAI, ollama
    public var displayName: String {
        switch self {
        case .none: "Off"
        case .anthropic: "Anthropic"
        case .openAI: "OpenAI"
        case .ollama: "Local (Ollama)"
        }
    }
}

/// User preferences. Persisted to UserDefaults on every change.
@MainActor
@Observable
public final class IslandSettings {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var loading = false

    // General
    public var islandEnabled = true { didSet { save() } }
    public var launchAtLogin = false { didSet { save() } }
    public var display: DisplaySelection = .automatic { didSet { save() } }
    // Appearance
    public var glassIntensity: Double = 0.6 { didSet { save() } }
    public var islandScale: Double = 1.0 { didSet { save() } }
    public var cornerRadius: Double = 32 { didSet { save() } }
    /// Compact Island background: see-through glass (default) or solid black like the hardware notch.
    public var compactGlass = true { didSet { save() } }
    /// Show the song title next to the artwork in the compact Island (wider; covers more menu bar).
    public var compactShowsTitle = false { didSet { save() } }
    // Behavior
    public var hoverExpansion = true { didSet { save() } }
    public var hoverDelay: Double = 0.06 { didSet { save() } }
    /// How long the Island stays open after the pointer leaves it.
    public var collapseDelay: Double = 0.7 { didSet { save() } }
    public var autoCollapse = true { didSet { save() } }
    public var autoCollapseDelay: Double = 4 { didSet { save() } }
    public var animationSpeed: Double = 1.0 { didSet { save() } }
    public var hapticFeedback = true { didSet { save() } }
    // Activities
    public var enabledKinds: Set<ActivityKind> = IslandSettings.defaultKinds { didSet { save() } }
    public var browserMediaEnabled = false { didSet { save() } }
    // Search
    public var searchEnabled = true { didSet { save() } }
    public var searchShortcut: IslandShortcut = .defaultSearch { didSet { save() } }
    public var webSearchEnabled = true { didSet { save() } }
    public var webSearchProviders: Set<String> = ["wikipedia", "duckduckgo"] { didSet { save() } }
    public var fileSearchEnabled = true { didSet { save() } }
    // AI
    public var aiProvider: AIProviderKind = .none { didSet { save() } }
    public var aiModel: String = "" { didSet { save() } }
    // Accessibility (forced overrides on top of the system settings)
    public var forceReduceMotion = false { didSet { save() } }
    public var forceReduceTransparency = false { didSet { save() } }
    public var forceHighContrast = false { didSet { save() } }
    // Advanced
    public var debugMode = false { didSet { save() } }
    public var performanceOverlay = false { didSet { save() } }

    public static let defaultKinds: Set<ActivityKind> = [.media, .timer, .download, .recording, .battery, .network, .device, .search, .notification, .custom, .call]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    public func resetToDefaults() {
        let fresh = IslandSettings(defaults: UserDefaults(suiteName: "island.defaults.\(UUID().uuidString)")!)
        loading = true
        apply(fresh.snapshot())
        loading = false
        save()
    }

    // MARK: Persistence

    struct Snapshot: Codable {
        var islandEnabled: Bool?
        var launchAtLogin: Bool?
        var display: DisplaySelection?
        var glassIntensity: Double?
        var islandScale: Double?
        var cornerRadius: Double?
        var compactGlass: Bool?
        var compactShowsTitle: Bool?
        var collapseDelay: Double?
        var hoverExpansion: Bool?
        var hoverDelay: Double?
        var autoCollapse: Bool?
        var autoCollapseDelay: Double?
        var animationSpeed: Double?
        var hapticFeedback: Bool?
        var enabledKinds: [ActivityKind]?
        var browserMediaEnabled: Bool?
        var searchEnabled: Bool?
        var searchShortcut: IslandShortcut?
        var webSearchEnabled: Bool?
        var webSearchProviders: [String]?
        var fileSearchEnabled: Bool?
        var aiProvider: AIProviderKind?
        var aiModel: String?
        var forceReduceMotion: Bool?
        var forceReduceTransparency: Bool?
        var forceHighContrast: Bool?
        var debugMode: Bool?
        var performanceOverlay: Bool?
    }

    static let storageKey = "island.settings.v1"

    func snapshot() -> Snapshot {
        Snapshot(islandEnabled: islandEnabled, launchAtLogin: launchAtLogin, display: display, glassIntensity: glassIntensity,
                 islandScale: islandScale, cornerRadius: cornerRadius, compactGlass: compactGlass,
                 compactShowsTitle: compactShowsTitle, collapseDelay: collapseDelay, hoverExpansion: hoverExpansion, hoverDelay: hoverDelay,
                 autoCollapse: autoCollapse, autoCollapseDelay: autoCollapseDelay, animationSpeed: animationSpeed,
                 hapticFeedback: hapticFeedback, enabledKinds: enabledKinds.map { $0 }.sorted { $0.rawValue < $1.rawValue },
                 browserMediaEnabled: browserMediaEnabled, searchEnabled: searchEnabled, searchShortcut: searchShortcut,
                 webSearchEnabled: webSearchEnabled, webSearchProviders: webSearchProviders.sorted(),
                 fileSearchEnabled: fileSearchEnabled, aiProvider: aiProvider, aiModel: aiModel,
                 forceReduceMotion: forceReduceMotion, forceReduceTransparency: forceReduceTransparency,
                 forceHighContrast: forceHighContrast, debugMode: debugMode, performanceOverlay: performanceOverlay)
    }

    private func apply(_ s: Snapshot) {
        if let v = s.islandEnabled { islandEnabled = v }
        if let v = s.launchAtLogin { launchAtLogin = v }
        if let v = s.display { display = v }
        if let v = s.glassIntensity { glassIntensity = min(1, max(0, v)) }
        if let v = s.islandScale { islandScale = min(1.3, max(0.8, v)) }
        if let v = s.cornerRadius { cornerRadius = min(48, max(12, v)) }
        if let v = s.compactGlass { compactGlass = v }
        if let v = s.compactShowsTitle { compactShowsTitle = v }
        if let v = s.collapseDelay { collapseDelay = min(3, max(0.1, v)) }
        if let v = s.hoverExpansion { hoverExpansion = v }
        // 0.12 was the previous default; move untouched installs to the snappier one.
        if let v = s.hoverDelay { hoverDelay = v == 0.12 ? 0.06 : min(1, max(0, v)) }
        if let v = s.autoCollapse { autoCollapse = v }
        if let v = s.autoCollapseDelay { autoCollapseDelay = min(30, max(1, v)) }
        if let v = s.animationSpeed { animationSpeed = min(2, max(0.5, v)) }
        if let v = s.hapticFeedback { hapticFeedback = v }
        if let v = s.enabledKinds { enabledKinds = Set(v) }
        if let v = s.browserMediaEnabled { browserMediaEnabled = v }
        if let v = s.searchEnabled { searchEnabled = v }
        if let v = s.searchShortcut { searchShortcut = v }
        if let v = s.webSearchEnabled { webSearchEnabled = v }
        if let v = s.webSearchProviders { webSearchProviders = Set(v) }
        if let v = s.fileSearchEnabled { fileSearchEnabled = v }
        if let v = s.aiProvider { aiProvider = v }
        if let v = s.aiModel { aiModel = v }
        if let v = s.forceReduceMotion { forceReduceMotion = v }
        if let v = s.forceReduceTransparency { forceReduceTransparency = v }
        if let v = s.forceHighContrast { forceHighContrast = v }
        if let v = s.debugMode { debugMode = v }
        if let v = s.performanceOverlay { performanceOverlay = v }
    }

    private func load() {
        loading = true
        defer { loading = false }
        guard let data = defaults.data(forKey: Self.storageKey),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        apply(snap)
    }

    private func save() {
        guard !loading, let data = try? JSONEncoder().encode(snapshot()) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
