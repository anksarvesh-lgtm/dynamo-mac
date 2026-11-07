// SPDX-License-Identifier: MIT
import Foundation
import NotchCore
import NotchFeatures
import Observation
import SwiftUI

/// A provider the Usage tab can show.
public struct UsageProvider: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    /// Its usage page on the web, opened in the browser.
    let dashboard: URL?
}

/// How much of each AI coding subscription is used, in the notch.
///
/// The providers are OpenUsage's (MIT, vendored in `OpenUsage/`). Nothing reaches the network for a
/// provider until the user turns it on; then it reads only the sign-in its own tool keeps on this Mac
/// and sends it only to its own service. The tab refreshes what's stale when it opens and every five
/// minutes while it stays open. Refreshing in the background is the user's choice, off by default.
/// The last results are cached, so the tab paints at once. PRIVACY.md has the full list.
@MainActor
@Observable
public final class UsageFeature: NotchFeature {
    /// How often providers refresh while the Usage tab isn't on screen.
    public enum BackgroundRefresh: Int, CaseIterable, Identifiable, Sendable {
        case off = 0
        case quarterHour = 15
        case halfHour = 30
        case hour = 60

        public var id: Self { self }
        public var title: String { self == .off ? "Off" : "Every \(rawValue) minutes" }
    }

    public let id = FeatureID.usage
    public var phase: FeaturePhase = .stopped {
        didSet { if phase != oldValue { schedule() } }
    }
    /// Providers the user turned on.
    public private(set) var enabled: Set<String> {
        didSet { defaults.set(enabled.sorted(), forKey: Key.enabled) }
    }
    public var backgroundRefresh: BackgroundRefresh {
        didSet {
            defaults.set(backgroundRefresh.rawValue, forKey: Key.background)
            schedule()
        }
    }
    /// Providers whose tool is signed in on this Mac, from a local check.
    public private(set) var detected: Set<String> = []
    /// Whether that check has run, so the tab can say it's still looking.
    public private(set) var hasDetected = false
    public private(set) var refreshing: Set<String> = []
    /// The latest good result per provider.
    private(set) var snapshots: [String: ProviderSnapshot] = [:]
    /// Why each provider's last refresh failed, shown over its last good numbers.
    private(set) var errors: [String: String] = [:]
    /// Raised when a limit passes 80% or 95% while the Usage tab isn't on screen.
    @ObservationIgnored public var onActivity: ((Activity) -> Void)?
    /// Opens the AI Usage settings, where API keys go.
    @ObservationIgnored public var openSettings: (() -> Void)?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let cacheURL: URL
    @ObservationIgnored private let makeRuntimes: @MainActor () -> [ProviderRuntime]
    @ObservationIgnored private var runtimes: [ProviderRuntime]?
    @ObservationIgnored private var retryAfter: [String: Date] = [:]
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private let now: @Sendable () -> Date

    /// A result younger than this is shown as is.
    static let freshness: TimeInterval = 60
    /// After a failure, a provider isn't asked again for this long, unless the user asks.
    static let failureBackoff: TimeInterval = 60
    /// The longest one provider may take: a stuck provider is cancelled, not waited on.
    static let deadline: TimeInterval = 120
    static let visibleInterval: TimeInterval = 5 * 60

    public convenience init(defaults: UserDefaults = .standard) {
        self.init(
            defaults: defaults, cacheURL: AppSupport.file("usage-cache.json"),
            runtimes: { ProviderCatalog.make(defaults: defaults) })
    }

    init(
        defaults: UserDefaults, cacheURL: URL, runtimes: @escaping @MainActor () -> [ProviderRuntime],
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.cacheURL = cacheURL
        self.makeRuntimes = runtimes
        self.now = now
        let enabled = Set(defaults.stringArray(forKey: Key.enabled) ?? [])
        self.enabled = enabled
        backgroundRefresh = BackgroundRefresh(rawValue: defaults.integer(forKey: Key.background)) ?? .off
        let cached = (try? Data(contentsOf: cacheURL)).flatMap {
            try? JSONDecoder().decode([String: ProviderSnapshot].self, from: $0)
        }
        snapshots = (cached ?? [:]).filter { enabled.contains($0.key) }
    }

    public var view: some View { UsageView(usage: self) }

    /// Every provider, in OpenUsage's order.
    public var providers: [UsageProvider] {
        allRuntimes().map { runtime in
            // Its usage page; a status page or API key settings aren't what the tab is about.
            let page = runtime.provider.visibleLinks.first { !["Status", "API Keys"].contains($0.label) }
            return UsageProvider(
                id: runtime.provider.id, name: runtime.provider.displayName,
                dashboard: page.flatMap { URL(string: $0.url) })
        }
    }

    /// Enabled providers in order, for the tab.
    var enabledProviders: [UsageProvider] { providers.filter { enabled.contains($0.id) } }

    // MARK: API keys

    /// Providers with no sign-in of their own to reuse, and the variable each reads its API key from.
    /// A key pasted in Settings is kept in the keychain and read like that variable.
    nonisolated static let apiKeyNames = [
        "openrouter": OpenRouterAuthStore.environmentNames[0], "zai": ZAIAuthStore.environmentNames[0],
    ]

    /// Where a provider's API key comes from.
    enum KeySource { case keychain, shell, configFile, none }

    func takesAPIKey(_ providerID: String) -> Bool { Self.apiKeyNames[providerID] != nil }

    func keySource(_ providerID: String) -> KeySource {
        guard let name = Self.apiKeyNames[providerID] else { return .none }
        if APIKeyVault.key(named: name) != nil { return .keychain }
        let runtime = allRuntimes().first { $0.provider.id == providerID } as? any APIKeyManaging
        switch runtime?.apiKeyStatus {
        case .fromEnvironment: return .shell
        case .saved, .overrideActive: return .configFile
        case .notSet, nil: return .none
        }
    }

    /// Keeps `key` in the keychain, then looks again, and refreshes the provider if it's on.
    func saveAPIKey(_ key: String, for providerID: String) throws {
        guard let name = Self.apiKeyNames[providerID] else { return }
        try APIKeyVault.save(key, named: name)
        keyChanged(providerID)
    }

    func removeAPIKey(for providerID: String) {
        guard let name = Self.apiKeyNames[providerID] else { return }
        APIKeyVault.delete(named: name)
        keyChanged(providerID)
    }

    private func keyChanged(_ providerID: String) {
        retryAfter[providerID] = nil
        Task {
            await detect()
            await refresh(providerID, force: true)
        }
    }

    public func isEnabled(_ providerID: String) -> Bool { enabled.contains(providerID) }

    /// Turning a provider on fetches it right away; turning it off forgets its results.
    public func setEnabled(_ providerID: String, _ on: Bool) {
        if on {
            enabled.insert(providerID)
            Task { await refresh(providerID, force: true) }
        } else {
            enabled.remove(providerID)
            snapshots[providerID] = nil
            errors[providerID] = nil
            retryAfter[providerID] = nil
            saveCache()
        }
        schedule()
    }

    /// Finds which providers' tools are signed in on this Mac from their files and keychain items.
    /// Never the network.
    public func detect() async {
        var found: Set<String> = []
        for runtime in allRuntimes() where await runtime.hasLocalCredentials() {
            found.insert(runtime.provider.id)
        }
        detected = found
        hasDetected = true
    }

    /// Refreshes every enabled provider at once, so a slow one never holds up the rest. `force` skips
    /// the freshness window and the failure backoff: the refresh button.
    public func refreshAll(force: Bool = false) async {
        let ids = allRuntimes().map(\.provider.id).filter(enabled.contains)
        let tasks = ids.map { id in Task { await self.refresh(id, force: force) } }
        for task in tasks { await task.value }
    }

    func refresh(_ providerID: String, force: Bool = false) async {
        guard enabled.contains(providerID), !refreshing.contains(providerID),
            let runtime = allRuntimes().first(where: { $0.provider.id == providerID })
        else { return }
        if !force {
            let fresh = snapshots[providerID].map { now().timeIntervalSince($0.refreshedAt) < Self.freshness } ?? false
            let backingOff = retryAfter[providerID].map { now() < $0 } ?? false
            if fresh || backingOff { return }
        }
        refreshing.insert(providerID)
        defer { refreshing.remove(providerID) }
        let result = await ProviderRefreshDeadline.snapshot(from: runtime, force: force, timeout: Self.deadline)
        guard !Task.isCancelled, enabled.contains(providerID) else { return }
        guard let snapshot = result else {
            return fail(providerID, "It didn't answer within \(Int(Self.deadline)) seconds.")
        }
        if let message = snapshot.errorMessage { return fail(providerID, message) }
        let previous = snapshots[providerID]
        snapshots[providerID] = snapshot
        errors[providerID] = nil
        retryAfter[providerID] = nil
        saveCache()
        if phase != .foreground, let alert = Self.alert(from: previous, to: snapshot) { onActivity?(alert) }
    }

    /// The most severe limit that passed 80% or 95% between two results, or else one that was past 80%
    /// and has reset, as a live activity. The first result for a provider isn't news.
    nonisolated static func alert(from old: ProviderSnapshot?, to new: ProviderSnapshot) -> Activity? {
        guard let old else { return nil }
        let before = Dictionary(old.meters.map { ($0.label, $0.fraction) }, uniquingKeysWith: max)
        let crossed = new.meters.compactMap { meter -> (Meter, Double)? in
            guard let threshold = [0.95, 0.8].first(where: { (before[meter.label] ?? 0) < $0 && meter.fraction >= $0 })
            else { return nil }
            return (meter, threshold)
        }
        guard let (meter, threshold) = crossed.max(by: { $0.0.fraction < $1.0.fraction }) else {
            // Usage only falls when its window starts over.
            guard let reset = new.meters.first(where: { (before[$0.label] ?? 0) >= 0.8 && $0.fraction < 0.5 })
            else { return nil }
            return Activity(
                feature: .usage, symbol: "arrow.counterclockwise.circle.fill", title: "\(new.displayName) reset",
                level: reset.fraction, duration: .seconds(4))
        }
        let percent = Int((min(meter.fraction, 1) * 100).rounded())
        return Activity(
            feature: .usage,
            symbol: threshold >= 0.95 ? "exclamationmark.triangle.fill" : "gauge.with.dots.needle.67percent",
            title: "\(new.displayName) \(percent)%", level: min(meter.fraction, 1), duration: .seconds(4))
    }

    // MARK: Lifecycle

    /// On screen: refresh what's stale now and every five minutes. Off screen: refresh only on the
    /// user's background interval. Stopped: nothing, and the providers are let go.
    private func schedule() {
        loop?.cancel()
        loop = nil
        let interval: TimeInterval? =
            switch phase {
            case .foreground: Self.visibleInterval
            case .background: backgroundRefresh == .off ? nil : TimeInterval(backgroundRefresh.rawValue * 60)
            case .stopped: nil
            }
        if phase == .stopped { runtimes = nil }
        if phase == .foreground {
            Task {
                if enabled.isEmpty { await detect() }
                await refreshAll()
            }
        }
        guard let interval, !enabled.isEmpty else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                await self?.refreshAll()
            }
        }
    }

    private func allRuntimes() -> [ProviderRuntime] {
        if let runtimes { return runtimes }
        let made = makeRuntimes()
        runtimes = made
        return made
    }

    private func fail(_ providerID: String, _ message: String) {
        errors[providerID] = message
        retryAfter[providerID] = now().addingTimeInterval(Self.failureBackoff)
        Log.features.error("Usage \(providerID, privacy: .public) didn't refresh")
    }

    private func saveCache() {
        do {
            try JSONEncoder().encode(snapshots).write(to: cacheURL, options: .atomic)
        } catch {
            Log.features.error("Couldn't save usage: \(error.localizedDescription, privacy: .public)")
        }
    }

    private enum Key {
        static let enabled = "usage.enabledProviders"
        static let background = "usage.backgroundRefreshMinutes"
    }
}

/// One bounded limit from a snapshot, like a session or weekly quota.
struct Meter: Identifiable, Hashable {
    var id: String { label }
    let label: String
    let used: Double
    let limit: Double
    let format: ProgressFormat
    let resetsAt: Date?
    let period: TimeInterval?

    var fraction: Double { limit > 0 ? used / limit : 0 }
}

extension ProviderSnapshot {
    /// Its bounded limits, in the provider's order: the first is the headline.
    var meters: [Meter] {
        lines.compactMap { line in
            guard case .progress(let label, let used, let limit, let format, let resetsAt, let periodMs, _) = line
            else { return nil }
            return Meter(
                label: label, used: used, limit: limit, format: format, resetsAt: resetsAt,
                period: periodMs.map { TimeInterval($0) / 1000 })
        }
    }

    /// The failure a provider reported instead of numbers, if any.
    var errorMessage: String? {
        for line in lines where line.isError {
            if case .badge(_, let text, _, _) = line { return text }
        }
        return nil
    }
}
