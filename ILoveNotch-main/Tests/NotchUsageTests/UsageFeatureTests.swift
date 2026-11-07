// SPDX-License-Identifier: MIT
import Foundation
import NotchCore
import Testing

@testable import NotchUsage

/// A provider that answers with whatever the test sets, and counts how often it was asked.
@MainActor
final class FakeRuntime: ProviderRuntime {
    let provider: Provider
    var widgetDescriptors: [WidgetDescriptor] { [] }
    var result: ProviderSnapshot
    var signedIn = true
    private(set) var refreshes = 0

    init(id: String, name: String, used: Double) {
        provider = Provider(id: id, displayName: name, icon: .providerMark(id))
        result = Self.snapshot(id: id, name: name, used: used)
    }

    func refresh() async -> ProviderSnapshot {
        refreshes += 1
        return result
    }

    func hasLocalCredentials() async -> Bool { signedIn }

    static func snapshot(id: String, name: String, used: Double, at date: Date = .now) -> ProviderSnapshot {
        ProviderSnapshot(
            providerID: id, displayName: name, plan: "Max",
            lines: [
                .progress(
                    label: "Session", used: used, limit: 100, format: .percent,
                    resetsAt: date.addingTimeInterval(2 * 3600), periodDurationMs: 5 * 3_600_000),
                .progress(label: "Weekly", used: used / 2, limit: 100, format: .percent),
            ],
            refreshedAt: date)
    }
}

@MainActor
struct UsageFeatureTests {
    private let defaults = UserDefaults(suiteName: "UsageFeatureTests.\(UUID().uuidString)")!
    private let cache = FileManager.default.temporaryDirectory.appending(path: "usage-\(UUID().uuidString).json")
    private let claude = FakeRuntime(id: "claude", name: "Claude", used: 42)
    private let codex = FakeRuntime(id: "codex", name: "Codex", used: 10)

    private func makeUsage() -> UsageFeature {
        UsageFeature(defaults: defaults, cacheURL: cache, runtimes: { [claude, codex] in [claude, codex] })
    }

    @Test func nothingIsAskedUntilAProviderIsTurnedOn() async {
        let usage = makeUsage()
        await usage.refreshAll()
        #expect(claude.refreshes == 0 && codex.refreshes == 0)
        #expect(usage.providers.map(\.id) == ["claude", "codex"])

        usage.setEnabled("claude", true)
        #expect(await eventually { usage.snapshots["claude"] != nil }, "turning one on fetches it at once")
        #expect(claude.refreshes == 1 && usage.snapshots["claude"]?.meters.first?.used == 42)
        #expect(codex.refreshes == 0, "the others stay untouched")
    }

    @Test func aFreshResultIsReusedUnlessTheUserAsks() async {
        let usage = makeUsage()
        usage.setEnabled("claude", true)
        #expect(await eventually { usage.snapshots["claude"] != nil })
        await usage.refreshAll()
        #expect(claude.refreshes == 1, "younger than a minute: shown as is")
        await usage.refreshAll(force: true)
        #expect(claude.refreshes == 2, "the refresh button always asks")
    }

    @Test func aFailureKeepsTheLastGoodNumbersAndBacksOff() async {
        let usage = makeUsage()
        usage.setEnabled("claude", true)
        #expect(await eventually { usage.snapshots["claude"] != nil })
        claude.result = .error(provider: claude.provider, message: "Sign in to Claude Code again")
        await usage.refreshAll(force: true)
        #expect(usage.errors["claude"] == "Sign in to Claude Code again")
        #expect(usage.snapshots["claude"]?.meters.first?.used == 42, "the last good numbers stay")
        let asked = claude.refreshes
        await usage.refresh("claude")
        #expect(claude.refreshes == asked, "a failed provider isn't asked again right away")
    }

    @Test func choicesAndResultsSurviveARelaunch() async {
        let usage = makeUsage()
        usage.setEnabled("claude", true)
        usage.backgroundRefresh = .halfHour
        #expect(await eventually { usage.snapshots["claude"] != nil })

        let relaunched = makeUsage()
        #expect(relaunched.isEnabled("claude") && !relaunched.isEnabled("codex"))
        #expect(relaunched.backgroundRefresh == .halfHour)
        #expect(relaunched.snapshots["claude"]?.meters.first?.used == 42, "the cache paints at once")
    }

    @Test func turningAProviderOffForgetsIt() async {
        let usage = makeUsage()
        usage.setEnabled("claude", true)
        #expect(await eventually { usage.snapshots["claude"] != nil })
        usage.setEnabled("claude", false)
        #expect(usage.snapshots["claude"] == nil && !usage.isEnabled("claude"))
        #expect(makeUsage().snapshots["claude"] == nil, "and its cached result")
    }

    @Test func detectionOnlyLooksLocally() async {
        codex.signedIn = false
        let usage = makeUsage()
        #expect(!usage.hasDetected)
        await usage.detect()
        #expect(usage.detected == ["claude"] && usage.hasDetected)
        #expect(claude.refreshes == 0, "detection never fetches")
    }

    @Test func limitsPassing80And95PercentRaiseAnActivity() throws {
        let at70 = FakeRuntime.snapshot(id: "claude", name: "Claude", used: 70)
        let at85 = FakeRuntime.snapshot(id: "claude", name: "Claude", used: 85)
        let at96 = FakeRuntime.snapshot(id: "claude", name: "Claude", used: 96)
        let close = try #require(UsageFeature.alert(from: at70, to: at85))
        #expect(close.title == "Claude 85%" && close.level == 0.85 && close.feature == .usage)
        let almostOut = try #require(UsageFeature.alert(from: at85, to: at96))
        #expect(almostOut.symbol == "exclamationmark.triangle.fill")
        #expect(UsageFeature.alert(from: nil, to: at96) == nil, "the first result isn't news")
        #expect(UsageFeature.alert(from: at85, to: at85) == nil, "nor is staying above a line")
    }

    @Test func aLimitThatWasCloseAndResetsSaysSo() throws {
        let at10 = FakeRuntime.snapshot(id: "claude", name: "Claude", used: 10)
        let at30 = FakeRuntime.snapshot(id: "claude", name: "Claude", used: 30)
        let at90 = FakeRuntime.snapshot(id: "claude", name: "Claude", used: 90)
        let reset = try #require(UsageFeature.alert(from: at90, to: at10))
        #expect(reset.title == "Claude reset" && reset.level == 0.1)
        #expect(UsageFeature.alert(from: at30, to: at10) == nil, "a limit nowhere near its end isn't news")
    }

    @Test func eachProviderLinksToItsUsagePageNotItsStatusPage() {
        let usage = UsageFeature(
            defaults: defaults, cacheURL: cache, runtimes: { [defaults] in ProviderCatalog.make(defaults: defaults) })
        let pages = Dictionary(uniqueKeysWithValues: usage.providers.map { ($0.id, $0.dashboard?.absoluteString) })
        #expect(pages["claude"] == "https://claude.ai/settings/usage")
        #expect(pages["codex"] == "https://chatgpt.com/codex/settings/usage")
        #expect(pages["ollama"] == "https://ollama.com/settings", "not its API keys")
    }

    @Test func onlyOpenRouterAndZaiTakeAKeyAndOnlyTheAppTouchesTheKeychain() {
        let usage = makeUsage()
        #expect(usage.takesAPIKey("openrouter") && usage.takesAPIKey("zai") && !usage.takesAPIKey("claude"))
        #expect(APIKeyVault.names == ["OPENROUTER_API_KEY", "ZAI_API_KEY"], "the variables a saved key stands in for")
        #expect(APIKeyVault.key(named: "OPENROUTER_API_KEY") == nil, "a test runner never reads the keychain")
        #expect(throws: APIKeyVault.VaultError.self) { try APIKeyVault.save("sk-or-test", named: "OPENROUTER_API_KEY") }
    }

    @Test func openUsagesCatalogBuildsEveryProvider() {
        let ids = ProviderCatalog.make(defaults: defaults).map(\.provider.id)
        #expect(
            ids == [
                "claude", "codex", "cursor", "antigravity", "copilot", "devin", "grok", "ollama", "opencode",
                "openrouter", "zai",
            ])
    }
}

/// Waits until `condition` holds, checking every 10 ms, for at most 30 seconds: long enough for a
/// busy CI runner, where tests share the main actor.
@MainActor
func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(30)
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}
