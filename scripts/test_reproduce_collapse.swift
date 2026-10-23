import Foundation
import AppKit

// MARK: - Mock State & Geometry matching LiquidDynamo
struct MockGeometry {
    let rawNotchWidth: CGFloat = 180.0
    let notchHeight: CGFloat = 32.0
    let compactPillWidth: CGFloat = 220.0
    let isNotched: Bool = true
    let exclusionHeight: CGFloat = 32.0
    let rawNotchHeight: CGFloat = 32.0
    let wingWidth: CGFloat = 40.0
    let notchRect: NSRect = NSRect(x: 774, y: 1085, width: 180, height: 32)
}

enum OrganicItem: Equatable, CustomStringConvertible {
    case none
    case clipboard
    case dropper
    case device(String)
    case storageCleaner
    case colorDropper

    var description: String {
        switch self {
        case .none: return "none"
        case .clipboard: return "clipboard"
        case .dropper: return "dropper"
        case .device(let k): return "device(\(k))"
        case .storageCleaner: return "storageCleaner"
        case .colorDropper: return "colorDropper"
        }
    }
}

enum State {
    case idle, compact, minimal, expanded, alertPop
}

print("=== STARTING REPRODUCTION SIMULATION FOR ICON CLICK COLLAPSE ===")

// Screen geometry: 1728 x 1117 (MacBook Pro 16")
let screenFrame = NSRect(x: 0, y: 0, width: 1728, height: 1117)
let topY = screenFrame.maxY // 1117
let notchRect = NSRect(x: 774, y: 1085, width: 180, height: 32)
let geom = MockGeometry()

var state: State = .idle
var isPinnedOpen: Bool = false
var isHovering: Bool = false
var activeOrganicItem: OrganicItem = .none
var targetSize = CGSize(width: 180, height: 32)
var windowFrame = NSRect(x: 774, y: 1085, width: 180, height: 32)
var lastReportedMeasuredHeight: CGFloat = 0

func isMouseInHoverRegion(_ screenPoint: NSPoint) -> Bool {
    if state != .expanded {
        let minX = notchRect.minX
        let maxX = notchRect.maxX
        let minY = notchRect.minY
        let maxY = topY + 1.0
        return screenPoint.x >= minX && screenPoint.x <= maxX && screenPoint.y >= minY && screenPoint.y <= maxY
    } else {
        let islandW = targetSize.width
        let islandH = targetSize.height
        let minX = notchRect.midX - (islandW / 2.0) - 20.0
        let maxX = notchRect.midX + (islandW / 2.0) + 20.0
        let minY = topY - islandH - 20.0
        let maxY = topY + 1.0
        return screenPoint.x >= minX && screenPoint.x <= maxX && screenPoint.y >= minY && screenPoint.y <= maxY
    }
}

func containsPointInVisibleShape(_ screenPoint: NSPoint) -> Bool {
    if state == .expanded {
        return isMouseInHoverRegion(screenPoint) || windowFrame.contains(screenPoint)
    }
    return isMouseInHoverRegion(screenPoint)
}

func minimumHeight(for item: OrganicItem) -> CGFloat {
    switch item {
    case .none: return max(180, geom.notchHeight + 150) // 182
    case .clipboard: return max(400, geom.notchHeight + 380) // 412
    case .dropper: return max(320, geom.notchHeight + 300) // 332
    case .device: return max(380, geom.notchHeight + 350) // 382
    case .storageCleaner: return max(400, geom.notchHeight + 370)
    case .colorDropper: return max(320, geom.notchHeight + 300)
    }
}

func calculateDimensions(for s: State) -> CGSize {
    switch s {
    case .idle, .compact:
        return CGSize(width: 220, height: 32)
    case .minimal:
        return CGSize(width: 220, height: 32)
    case .expanded:
        switch activeOrganicItem {
        case .none:
            let size = CGSize(width: 500, height: 207)
            print("[COLLAPSE] IslandController.calculateDimensions(.expanded): branch=home(none), size=\(size)")
            return size
        case .clipboard:
            let size = CGSize(width: 520, height: 462)
            print("[COLLAPSE] IslandController.calculateDimensions(.expanded): branch=home(clipboard), size=\(size)")
            return size
        case .dropper:
            let size = CGSize(width: 500, height: 352)
            print("[COLLAPSE] IslandController.calculateDimensions(.expanded): branch=home(dropper), size=\(size)")
            return size
        case .device(let k):
            let size = CGSize(width: 520, height: 422)
            print("[COLLAPSE] IslandController.calculateDimensions(.expanded): branch=home(device(\(k))), size=\(size)")
            return size
        default:
            return CGSize(width: 500, height: 400)
        }
    case .alertPop:
        return CGSize(width: 280, height: 40)
    }
}

func transitionTo(_ newState: State, caller: String = "unknown") {
    let oldState = state
    state = newState
    let newSize = calculateDimensions(for: newState)
    targetSize = newSize
    print("[COLLAPSE] IslandController.transitionTo: \(oldState) -> \(newState), caller=\(caller)")
    if newState != .expanded {
        activeOrganicItem = .none
        isPinnedOpen = false
    }
}

func onHoverEntered(mouseLoc: NSPoint) {
    let inRegion = isMouseInHoverRegion(mouseLoc)
    print("[COLLAPSE] IslandController.onHoverEntered: mouse=\(mouseLoc), isPinnedOpen=\(isPinnedOpen), state=\(state), targetSize=\(targetSize), inHoverRegion=\(inRegion)")
    isHovering = true
    guard state != .expanded else { return }
    isPinnedOpen = false
    transitionTo(.expanded, caller: "onHoverEntered")
    updateWindowFrame(for: .expanded, animated: false)
}

func onHoverExited(mouseLoc: NSPoint) {
    let inRegion = isMouseInHoverRegion(mouseLoc)
    print("[COLLAPSE] IslandController.onHoverExited: mouse=\(mouseLoc), isPinnedOpen=\(isPinnedOpen), state=\(state), targetSize=\(targetSize), inHoverRegion=\(inRegion)")
    isHovering = false
    guard state == .expanded else { return }
    guard !isPinnedOpen else {
        print("  -> onHoverExited returned because isPinnedOpen=true")
        return
    }
    guard activeOrganicItem == .none else {
        print("  -> onHoverExited returned because activeOrganicItem != .none (\(activeOrganicItem))")
        return
    }
    print("  -> onHoverExited COLLAPSE FIRED! activeOrganicItem=.none, transitionTo(.compact)")
    activeOrganicItem = .none
    transitionTo(.compact, caller: "onHoverExited")
    updateWindowFrame(for: .compact, animated: true)
}

func updateWindowFrame(for s: State, animated: Bool) {
    let target = targetSize
    let originX = notchRect.midX - (target.width / 2.0)
    let originY = topY - target.height
    windowFrame = NSRect(x: originX, y: originY, width: target.width, height: target.height)
    print("[COLLAPSE] AppDelegate.updateWindowFrame: state=\(s), targetSize=\(target), frame=\(windowFrame), animated=\(animated)")
}

func checkCursorHover(mouseLoc: NSPoint) {
    let inRegion = isMouseInHoverRegion(mouseLoc)
    if inRegion {
        if !isHovering { onHoverEntered(mouseLoc: mouseLoc) }
    } else {
        if isHovering { onHoverExited(mouseLoc: mouseLoc) }
    }
}

func clickOutsideMonitor(clickPoint: NSPoint) {
    let inside = containsPointInVisibleShape(clickPoint)
    print("[COLLAPSE] clickOutsideMonitor check: window.frame=\(windowFrame), clickPoint=\(clickPoint), containsPointInVisibleShape=\(inside)")
    print("[COLLAPSE] clickOutsideMonitor: mouseLoc=\(clickPoint), clickedInside=\(inside), willRunVmClose=\(!inside)")
    if !inside {
        print("[COLLAPSE] clickOutsideMonitor calling vm.close()")
        vmClose()
    }
}

func vmClose() {
    print("[COLLAPSE] LiquidViewModel.close() called, isPinnedOpen=\(isPinnedOpen)")
    isPinnedOpen = false
    transitionTo(.compact, caller: "vmClose")
    updateWindowFrame(for: .compact, animated: false)
}

func adjustTargetHeightIfNeeded(_ measuredHeight: CGFloat) {
    guard state == .expanded else { return }
    let minH = minimumHeight(for: activeOrganicItem)
    let effectiveMeasured = max(measuredHeight, minH)
    lastReportedMeasuredHeight = effectiveMeasured
    let neededH = effectiveMeasured + 14.0
    print("[COLLAPSE] IslandController.adjustTargetHeightIfNeeded: measuredHeight=\(measuredHeight), neededH=\(neededH), targetSize.height=\(targetSize.height)")
    if abs(targetSize.height - neededH) >= 8.0 {
        let currentMin = minimumHeight(for: activeOrganicItem)
        let finalH = max(neededH, currentMin)
        targetSize.height = finalH
        print("  -> targetSize.height adjusted to \(finalH)")
        updateWindowFrame(for: .expanded, animated: true)
    }
}

// ==========================================
// SCENARIO 1: Hover-open, then click device icon
// ==========================================
print("\n--- 1. User moves cursor into closed notch hitbox ---")
let hoverNotchPoint = NSPoint(x: 864, y: 1100)
checkCursorHover(mouseLoc: hoverNotchPoint)

print("\n--- 2. Island is open via hover: isPinnedOpen=\(isPinnedOpen), state=\(state) ---")

print("\n--- 3. User moves cursor down to Connected Device icon ---")
// Icon row is at y ≈ 1025, x ≈ 780
let iconPoint = NSPoint(x: 780, y: 1025)
checkCursorHover(mouseLoc: iconPoint)

print("\n--- 4. User CLICKS the Connected Device icon ---")
// 4a. Left mouse down fires click-outside monitor
clickOutsideMonitor(clickPoint: iconPoint)

// 4b. Button action runs
print("\n--- 4b. Button Action executing for Device 'bt_airpods' ---")
let oldItem = activeOrganicItem
let newItem = OrganicItem.device("bt_airpods")
isPinnedOpen = true
let targetBefore = targetSize
activeOrganicItem = newItem
let newTarget = calculateDimensions(for: .expanded)
targetSize = newTarget
print("[COLLAPSE] IslandController.activeOrganicItem didSet: oldValue=\(oldItem) -> newValue=\(newItem), targetSize before=\(targetBefore), after=\(targetSize)")
updateWindowFrame(for: .expanded, animated: true)

// 4c. Window resize animation starts; tracking area rebuild triggers mouseExited check
print("\n--- 4c. Window resize starts: AppKit tracking area rebuild triggers mouseExited check ---")
// What if cursor is checked during resize?
checkCursorHover(mouseLoc: iconPoint)

// 4d. SwiftUI preference key fires with height measurement
print("\n--- 4d. SwiftUI layout pass reports measuredHeight ---")
// Before detail card renders (or during initial frame): measuredHeight = 175
adjustTargetHeightIfNeeded(175)

// After detail card renders: measuredHeight = 282
adjustTargetHeightIfNeeded(282)

print("\n=== SIMULATION COMPLETED ===")
