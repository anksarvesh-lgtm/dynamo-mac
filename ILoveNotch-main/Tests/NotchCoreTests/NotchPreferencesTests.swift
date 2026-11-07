// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation
import Testing

@testable import NotchCore

@MainActor
struct NotchPreferencesTests {
    /// A throwaway defaults domain per test.
    private let defaults = UserDefaults(suiteName: "NotchPreferencesTests.\(UUID().uuidString)")!
    /// Every tab except those that start off, like the camera mirror.
    private let defaultTabs = FeatureID.allCases.filter { !NotchPreferences.offByDefault.contains($0) }

    @Test func everythingButTheMirrorIsEnabledOnOneDisplayByDefault() {
        let preferences = NotchPreferences(defaults: defaults)
        #expect(preferences.tabs == defaultTabs)
        #expect(!preferences.isEnabled(.mirror))
        #expect(!preferences.showOnAllDisplays)
        #expect(preferences.showsVolume && preferences.showsBattery)
        #expect(!preferences.replacesVolumeDisplay && !preferences.showsAccessoryBattery)
    }

    @Test func choicesPersistAcrossLaunches() {
        let first = NotchPreferences(defaults: defaults)
        first.setEnabled(.media, false)
        first.showOnAllDisplays = true
        first.showsBattery = false

        let second = NotchPreferences(defaults: defaults)
        #expect(!second.isEnabled(.media))
        #expect(second.tabs == defaultTabs.filter { $0 != .media })
        #expect(second.showOnAllDisplays)
        #expect(!second.showsBattery)
    }

    @Test func aFeatureThatStartsOffDoesSoOnceThenFollowsTheUser() {
        // An update from before the mirror existed: some choices stored, the mirror never seen.
        defaults.set(["notes"], forKey: "disabledFeatures")
        let updated = NotchPreferences(defaults: defaults)
        #expect(!updated.isEnabled(.mirror) && !updated.isEnabled(.notes))

        updated.setEnabled(.mirror, true)
        #expect(NotchPreferences(defaults: defaults).isEnabled(.mirror), "turned on, it stays on")
    }

    @Test func unknownStoredFeaturesAreIgnored() {
        defaults.set(["notes", "a-feature-from-the-future"], forKey: "disabledFeatures")
        let disabled = NotchPreferences(defaults: defaults).disabledFeatures
        #expect(disabled == [.notes, .mirror], "and the mirror starts off")
    }

    @Test func tabsMoveAndKeepTheirPlaceWhileHidden() {
        let preferences = NotchPreferences(defaults: defaults)
        preferences.place(.timer, at: 0)
        #expect(preferences.tabs.first == .timer)
        preferences.setEnabled(.shelf, false)
        preferences.place(.notes, at: 1)
        #expect(preferences.tabs.prefix(3) == [.timer, .notes, .media])
        #expect(preferences.tabOrder.prefix(5) == [.timer, .notes, .media, .sound, .shelf], "the hidden shelf stayed")
        preferences.place(.shelf, at: preferences.tabs.count)
        #expect(preferences.tabs.last == .shelf && preferences.isEnabled(.shelf), "placing a hidden tab shows it")
        #expect(NotchPreferences(defaults: defaults).tabs == preferences.tabs, "and the order persists")
    }

    @Test func anAppKeptInTheDrawerStaysOnButLeavesTheRow() {
        let preferences = NotchPreferences(defaults: defaults)
        preferences.moveToDrawer(.notes)
        #expect(preferences.isEnabled(.notes), "still on, so the notch can open it")
        #expect(preferences.tabs.contains(.notes) && !preferences.rowTabs.contains(.notes))
        #expect(!NotchPreferences(defaults: defaults).rowTabs.contains(.notes), "and it stays in the drawer")
        preferences.place(.notes, at: 0)
        #expect(preferences.rowTabs.first == .notes, "placing it puts it back on the row")
        preferences.moveToDrawer(.shelf)
        preferences.reset()
        #expect(preferences.rowTabs == defaultTabs)
    }

    @Test func aFeatureAddedByAnUpdateJoinsTheEndOfACustomOrder() {
        defaults.set(["timer", "media", "a-feature-from-the-future", "timer"], forKey: "tabOrder")
        let order = NotchPreferences(defaults: defaults).tabOrder
        #expect(order.prefix(2) == [.timer, .media])
        #expect(Array(order.dropFirst(2)) == FeatureID.allCases.filter { $0 != .timer && $0 != .media })
        #expect(!NotchPreferences(defaults: defaults, unavailable: [.usage]).tabOrder.contains(.usage))
    }

    @Test func resetRestoresTheDefaults() {
        let preferences = NotchPreferences(defaults: defaults)
        preferences.place(.timer, at: 0)
        preferences.setEnabled(.shelf, false)
        preferences.showOnAllDisplays = true
        preferences.resizeExpanded(to: CGSize(width: 600, height: 400))
        preferences.setEnabled(.mirror, true)
        preferences.replacesVolumeDisplay = true
        preferences.theme = .glass
        preferences.reset()
        #expect(preferences.tabs == defaultTabs)
        #expect(preferences.tabOrder == FeatureID.allCases)
        #expect(preferences.expandedSize == NotchPreferences.defaultExpandedSize)
        #expect(!preferences.replacesVolumeDisplay)
        #expect(preferences.theme == .black)
        #expect(!NotchPreferences(defaults: defaults).showOnAllDisplays)
    }

    @Test func theThemeIsBlackUntilChosenAndKept() {
        #expect(NotchPreferences(defaults: defaults).theme == .black)
        NotchPreferences(defaults: defaults).theme = .glass
        #expect(NotchPreferences(defaults: defaults).theme == .glass)
        defaults.set("chrome-from-the-future", forKey: "theme")
        #expect(NotchPreferences(defaults: defaults).theme == .black)
    }

    @Test func theNotchSizePersistsWithinItsLimits() {
        let preferences = NotchPreferences(defaults: defaults)
        preferences.resizeExpanded(to: CGSize(width: 600, height: 380))
        #expect(NotchPreferences(defaults: defaults).expandedSize == CGSize(width: 600, height: 380))
        preferences.resizeExpanded(to: CGSize(width: 5000, height: 10))
        #expect(preferences.expandedSize == CGSize(width: 720, height: 200))
        defaults.set([10.0, 9999.0], forKey: "expandedSize")  // a hand-edited value is clamped too
        #expect(NotchPreferences(defaults: defaults).expandedSize == CGSize(width: 414, height: 480))
    }

    @Test func theAnimationStylePersistsAndFallsBackToSpring() {
        #expect(NotchPreferences(defaults: defaults).animationStyle == .spring)
        NotchPreferences(defaults: defaults).animationStyle = .jelly
        #expect(NotchPreferences(defaults: defaults).animationStyle == .jelly)
        defaults.set("wobbly-from-the-future", forKey: "animationStyle")
        #expect(NotchPreferences(defaults: defaults).animationStyle == .spring)
    }

    @Test func theNotchShortcutStartsAsControlOptionOAndCanBeChangedOrCleared() {
        #expect(NotchPreferences(defaults: defaults).notchShortcut?.display == "⌃⌥O")
        #expect(NotchPreferences(defaults: defaults).clipboardShortcut?.display == "⌃⌥V")
        let command = KeyShortcut(keyCode: 49, modifiers: KeyShortcut.command | KeyShortcut.shift, key: "Space")
        NotchPreferences(defaults: defaults).notchShortcut = command
        #expect(NotchPreferences(defaults: defaults).notchShortcut == command)
        #expect(command.display == "⇧⌘Space", "modifiers read in the order menus show them")
        let cleared = NotchPreferences(defaults: defaults)
        cleared.notchShortcut = nil
        #expect(NotchPreferences(defaults: defaults).notchShortcut == nil, "cleared stays cleared")
        cleared.reset()
        #expect(NotchPreferences(defaults: defaults).notchShortcut == NotchPreferences.defaultNotchShortcut)
    }

    @Test func displaysWithoutANotchGetOneUnlessThePillIsPicked() {
        let preferences = NotchPreferences(defaults: defaults)
        #expect(preferences.notchlessStyle(for: "studio-display") == .notch)
        preferences.setNotchlessStyle(.pill, for: "studio-display")
        #expect(NotchPreferences(defaults: defaults).notchlessStyle(for: "studio-display") == .pill)
        #expect(NotchPreferences(defaults: defaults).notchlessStyle(for: "another-display") == .notch)
        preferences.reset()
        #expect(NotchPreferences(defaults: defaults).notchlessStyle(for: "studio-display") == .notch)
    }

    @Test func plusAndMinusResizeInProportion() {
        let preferences = NotchPreferences(defaults: defaults)
        var larger: [CGSize] = []
        while let next = preferences.expandedSizeStep(larger: true) {
            preferences.resizeExpanded(to: next)
            larger.append(preferences.expandedSize)
        }
        #expect(larger.map(\.width) == [515, 575, 644, 718], "+ stops at the largest size")
        var smaller: [CGSize] = []
        while let next = preferences.expandedSizeStep(larger: false) {
            preferences.resizeExpanded(to: next)
            smaller.append(preferences.expandedSize)
        }
        #expect(smaller.map(\.width) == [644, 575, 515, 460, 414, 414, 414], "− steps back down")
        #expect(smaller.suffix(3).map(\.height) == [261, 230, 200], "and ends on shorter sizes at the same width")
        #expect(smaller.last == NotchPreferences.minimumExpandedSize)

        let steps = NotchPreferences.expandedSizeSteps
        let aspect = NotchPreferences.defaultExpandedSize.width / NotchPreferences.defaultExpandedSize.height
        for step in steps.dropFirst(2) {
            #expect(abs(step.width / step.height - aspect) < 0.01, "the height follows the width")
        }
        #expect(steps.allSatisfy { NotchPreferences.clamped($0) == $0 }, "every step is within the limits")
    }

    @Test func observersRerunAfterEveryChange() async throws {
        let preferences = NotchPreferences(defaults: defaults)
        var seen: [[FeatureID]] = []
        observeContinuously { seen.append(preferences.tabs) }
        preferences.setEnabled(.tasks, false)
        #expect(await eventually { seen.count == 2 })
        preferences.setEnabled(.tasks, true)
        #expect(await eventually { seen.count == 3 })
        #expect(seen.last == defaultTabs)
    }
}
