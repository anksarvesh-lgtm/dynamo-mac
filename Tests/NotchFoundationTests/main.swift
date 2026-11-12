//
//  main.swift
//  NotchFoundationTests
//

import CoreGraphics
import Foundation

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("❌ Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

private func runStateMachineTests() {
    let customDurations = LiquidTransientDurations(peek: 2.0, hud: 1.5, activity: 5.0)

    // 1. Peek -> Activity -> HUD escalation ladder
    var result = LiquidNotchStateMachine.transition(
        from: .collapsed,
        on: .peekPosted(LiquidPeekPayload(id: "track-1")),
        durations: customDurations
    )
    check(result.next == .peek(LiquidPeekPayload(id: "track-1")), "Collapsed -> peek failed")
    check(result.autoDismissAfter == 2.0, "Peek duration mismatch")

    let activityID = LiquidActivityID(raw: "timer-1")
    result = LiquidNotchStateMachine.transition(
        from: result.next,
        on: .activityPosted(activityID),
        durations: customDurations
    )
    check(result.next == .activity(activityID), "Peek -> activity escalation failed")
    check(result.autoDismissAfter == 5.0, "Activity duration mismatch")

    // Peek should not downgrade active activity
    result = LiquidNotchStateMachine.transition(
        from: .activity(activityID),
        on: .peekPosted(LiquidPeekPayload(id: "track-2")),
        durations: customDurations
    )
    check(result.next == .activity(activityID), "Peek must not preempt activity")
    check(result.autoDismissAfter == nil, "Ignored peek must keep current timer")

    // HUD preempts activity
    result = LiquidNotchStateMachine.transition(
        from: .activity(activityID),
        on: .hudEvent(.volume),
        durations: customDurations
    )
    check(result.next == .hud(.volume), "HUD must preempt activity")
    check(result.autoDismissAfter == 1.5, "HUD duration mismatch")

    // Stale peek/activity timeout cannot dismiss HUD
    result = LiquidNotchStateMachine.transition(from: .hud(.volume), on: .timeout(.peek))
    check(result.next == .hud(.volume), "Stale peek timer must not dismiss HUD")
    result = LiquidNotchStateMachine.transition(from: .hud(.volume), on: .timeout(.activity))
    check(result.next == .hud(.volume), "Stale activity timer must not dismiss HUD")

    // Hover enter on HUD must not yank panel open mid volume change
    result = LiquidNotchStateMachine.transition(from: .hud(.volume), on: .hoverEnter)
    check(result.next == .hud(.volume), "Hover during HUD must not open expanded panel")

    // Matching HUD timeout returns to collapsed
    result = LiquidNotchStateMachine.transition(from: .hud(.volume), on: .timeout(.hud))
    check(result.next == .collapsed, "HUD timeout must collapse panel")

    // Pinned expanded resists clickAway, hoverExit, and swipe(.up), but obeys escape
    result = LiquidNotchStateMachine.transition(from: .expanded, on: .clickAway, pinned: true)
    check(result.next == .expanded, "Pinned expanded must resist clickAway")
    result = LiquidNotchStateMachine.transition(from: .expanded, on: .hoverExit, pinned: true)
    check(result.next == .expanded, "Pinned expanded must resist hoverExit")
    result = LiquidNotchStateMachine.transition(from: .expanded, on: .swipe(.up), pinned: true)
    check(result.next == .expanded, "Pinned expanded must resist swipe(.up)")
    result = LiquidNotchStateMachine.transition(from: .expanded, on: .escape, pinned: true)
    check(result.next == .collapsed, "Escape must always dismiss pinned expanded")

    // Unpinned expanded collapses cleanly on clickAway / hoverExit / swipe(.up)
    check(LiquidNotchStateMachine.transition(from: .expanded, on: .clickAway, pinned: false).next == .collapsed, "Unpinned clickAway must collapse")
    check(LiquidNotchStateMachine.transition(from: .expanded, on: .hoverExit, pinned: false).next == .collapsed, "Unpinned hoverExit must collapse")
    check(LiquidNotchStateMachine.transition(from: .expanded, on: .swipe(.up), pinned: false).next == .collapsed, "Unpinned swipe(.up) must collapse")

    // Activity dismissal respects exact ID
    check(LiquidNotchStateMachine.transition(from: .activity(activityID), on: .activityDismissed(LiquidActivityID(raw: "other"))).next == .activity(activityID), "Wrong activity ID must not dismiss")
    check(LiquidNotchStateMachine.transition(from: .activity(activityID), on: .activityDismissed(activityID)).next == .collapsed, "Matching activity ID must dismiss")
}

private func runDisplaySelectionTests() {
    check(LiquidDisplaySelection.targetIndices(of: [], mode: .all).isEmpty, "Empty screens should return []")
    check(LiquidDisplaySelection.primaryScreenIndex(in: []) == nil, "Empty screens should have nil primary index")

    let builtInSecondary = [
        LiquidScreenDescriptor(isBuiltIn: false, hasNotch: false, isMenuBarPrimary: true),
        LiquidScreenDescriptor(isBuiltIn: true, hasNotch: true, isMenuBarPrimary: false),
    ]
    check(LiquidDisplaySelection.targetIndices(of: builtInSecondary, mode: .all) == [0, 1], "All displays should select every index")
    check(LiquidDisplaySelection.targetIndices(of: builtInSecondary, mode: .builtInOnly) == [1], "builtInOnly should prefer built-in screen")
    check(LiquidDisplaySelection.primaryScreenIndex(in: builtInSecondary) == 1, "primaryScreenIndex should pick built-in")

    // Clamshell mode: no built-in, primary menu bar at index 1
    let clamshellScreens = [
        LiquidScreenDescriptor(isBuiltIn: false, hasNotch: false, isMenuBarPrimary: false),
        LiquidScreenDescriptor(isBuiltIn: false, hasNotch: false, isMenuBarPrimary: true),
    ]
    check(LiquidDisplaySelection.primaryScreenIndex(in: clamshellScreens) == 1, "Clamshell should fall back to menu-bar primary")

    // Degenerate external-only without origin (0,0) flag
    let fallbackOnly = [
        LiquidScreenDescriptor(isBuiltIn: false, hasNotch: false, isMenuBarPrimary: false),
        LiquidScreenDescriptor(isBuiltIn: false, hasNotch: false, isMenuBarPrimary: false),
    ]
    check(LiquidDisplaySelection.primaryScreenIndex(in: fallbackOnly) == 0, "Fallback should choose first screen")
}

private func runFullscreenEvaluatorTests() {
    let builtIn = FullscreenScreenDescriptor(
        screenUUID: "BUILTIN-UUID",
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeAreaTopInset: 32
    )
    let external = FullscreenScreenDescriptor(
        screenUUID: "EXT-UUID",
        frame: CGRect(x: 1512, y: -100, width: 2560, height: 1440),
        safeAreaTopInset: 0
    )
    let screens = [builtIn, external]
    let primaryHeight = FullscreenDetectorEvaluator.primaryHeight(for: screens)
    check(primaryHeight == 982, "Primary height mismatch: \(primaryHeight)")

    // External CG origin check: AppKit y=[-100, 1340], primaryHeight=982 => cgY = 982 - 1340 = -358
    let extCG = FullscreenDetectorEvaluator.convertAppKitScreenFrameToCG(external.frame, primaryScreenHeight: primaryHeight)
    check(extCG == CGRect(x: 1512, y: -358, width: 2560, height: 1440), "External CG conversion mismatch: \(extCG)")

    // 1. Notched built-in fullscreen (below 32pt safe area inset)
    let notchedFullscreenWin = FullscreenWindowDescriptor(
        ownerPID: 200,
        ownerBundleIdentifier: "com.apple.Safari",
        bounds: CGRect(x: 0, y: 32, width: 1512, height: 950),
        layer: 0,
        isOnScreen: true
    )
    // 2. Non-layer-0 window covering external monitor must NOT count
    let elevatedOverlay = FullscreenWindowDescriptor(
        ownerPID: 300,
        ownerBundleIdentifier: "com.example.overlay",
        bounds: extCG,
        layer: 25,
        isOnScreen: true
    )
    // 3. Excluded self PID covering external monitor must NOT count
    let selfWindow = FullscreenWindowDescriptor(
        ownerPID: 999,
        ownerBundleIdentifier: "com.agrigence.liquiddynamo",
        bounds: extCG,
        layer: 0,
        isOnScreen: true
    )
    let res1 = FullscreenDetectorEvaluator.evaluate(
        screens: screens,
        windows: [notchedFullscreenWin, elevatedOverlay, selfWindow],
        primaryScreenHeight: primaryHeight,
        excludedPID: 999,
        policy: .always
    )
    check(res1["BUILTIN-UUID"] == true, "Notched fullscreen window should match built-in screen")
    check(res1["EXT-UUID"] == false, "Elevated overlay and excluded PID must not trigger fullscreen")

    // 4. Split View / half-screen window must not trigger
    let splitWin = FullscreenWindowDescriptor(
        ownerPID: 201,
        ownerBundleIdentifier: "com.apple.TextEdit",
        bounds: CGRect(x: 0, y: 32, width: 756, height: 950),
        layer: 0,
        isOnScreen: true
    )
    let res2 = FullscreenDetectorEvaluator.evaluate(
        screens: screens,
        windows: [splitWin],
        primaryScreenHeight: primaryHeight,
        excludedPID: 999,
        policy: .always
    )
    check(res2["BUILTIN-UUID"] == false, "Split-view window must not trigger fullscreen")

    // 5. External screen true, built-in false, nowPlayingOnly case-insensitive matching
    let externalMusicWin = FullscreenWindowDescriptor(
        ownerPID: 555,
        ownerBundleIdentifier: "com.apple.Music",
        bounds: extCG,
        layer: 0,
        isOnScreen: true
    )
    let resMusicMatch = FullscreenDetectorEvaluator.evaluate(
        screens: screens,
        windows: [notchedFullscreenWin, externalMusicWin],
        primaryScreenHeight: primaryHeight,
        excludedPID: 999,
        policy: .nowPlayingOnly,
        activeMediaBundleIdentifier: "COM.APPLE.MUSIC"
    )
    check(resMusicMatch["BUILTIN-UUID"] == false, "Safari fullscreen should not hide under nowPlayingOnly while Music plays")
    check(resMusicMatch["EXT-UUID"] == true, "Matching active media bundle should trigger on external display")

    let resNoMedia = FullscreenDetectorEvaluator.evaluate(
        screens: screens,
        windows: [externalMusicWin],
        primaryScreenHeight: primaryHeight,
        excludedPID: 999,
        policy: .nowPlayingOnly,
        activeMediaBundleIdentifier: nil
    )
    check(resNoMedia["EXT-UUID"] == false, "nowPlayingOnly with nil active media should return false")

    // 6. Never policy
    let resNever = FullscreenDetectorEvaluator.evaluate(
        screens: screens,
        windows: [notchedFullscreenWin, externalMusicWin],
        primaryScreenHeight: primaryHeight,
        excludedPID: 999,
        policy: .never
    )
    check(resNever["BUILTIN-UUID"] == false && resNever["EXT-UUID"] == false, "Policy .never must force all false")

    // 7. Degenerate empty inputs
    check(
        FullscreenDetectorEvaluator.evaluate(
            screens: [],
            windows: [externalMusicWin],
            primaryScreenHeight: 0,
            policy: .always
        ).isEmpty,
        "Empty screens should return empty dictionary"
    )
}

@main
struct NotchFoundationTestRunner {
    static func main() {
        runStateMachineTests()
        runDisplaySelectionTests()
        runFullscreenEvaluatorTests()
        print("✅ NotchFoundationTests: all state machine, display selection, and fullscreen evaluator assertions passed.")
    }
}
