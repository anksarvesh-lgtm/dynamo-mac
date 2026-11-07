import Foundation
@testable import IslandCore

@MainActor
func registerSettingsTests() {
    let S = "Settings"

    test(S, "persists and reloads") {
        let suite = "island.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let s = IslandSettings(defaults: d)
        s.glassIntensity = 0.25
        s.hoverExpansion = false
        s.enabledKinds = [.media]
        s.display = .specific(name: "LG")
        s.searchShortcut = IslandShortcut(keyCode: 1, carbonModifiers: 256, display: "⌘S")
        let r = IslandSettings(defaults: d)
        expectEqual(r.glassIntensity, 0.25)
        expectEqual(r.hoverExpansion, false)
        expectEqual(r.enabledKinds, [.media])
        expectEqual(r.display, .specific(name: "LG"))
        expectEqual(r.searchShortcut.display, "⌘S")
        d.removePersistentDomain(forName: suite)
    }

    test(S, "clamps out-of-range persisted values") {
        let suite = "island.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.set(#"{"glassIntensity": 7, "animationSpeed": -3, "islandScale": 99}"#.data(using: .utf8), forKey: "island.settings.v1")
        let s = IslandSettings(defaults: d)
        expectEqual(s.glassIntensity, 1)
        expectEqual(s.animationSpeed, 0.5)
        expectEqual(s.islandScale, 1.3)
        d.removePersistentDomain(forName: suite)
    }

    test(S, "corrupt data falls back to defaults") {
        let suite = "island.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.set(Data("garbage".utf8), forKey: "island.settings.v1")
        let s = IslandSettings(defaults: d)
        expectEqual(s.glassIntensity, 0.6)
        expect(s.islandEnabled)
        d.removePersistentDomain(forName: suite)
    }

    test(S, "reset restores defaults") {
        let suite = "island.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let s = IslandSettings(defaults: d)
        s.cornerRadius = 12
        s.resetToDefaults()
        expectEqual(s.cornerRadius, 32)
        expectEqual(IslandSettings(defaults: d).cornerRadius, 32)
        d.removePersistentDomain(forName: suite)
    }
}
