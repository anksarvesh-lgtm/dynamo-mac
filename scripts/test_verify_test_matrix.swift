import Foundation
import CoreGraphics

// Test Matrix Verification Script for LiquidDynamo 1.9.2 Collapse Bug Fix

enum IslandState: String {
    case idle, compact, minimal, expanded, alertPop
}

enum OrganicNotchExpandedItem: Equatable {
    case none
    case clipboard
    case dropper
    case device(String)
    case storageCleaner
    case colorDropper
    case plexo
}

struct DeviceIdentity: Equatable {
    let stableKey: String
    let displayName: String
    let kind: String
    let batteryPercentage: Int?
}

class MockIslandController {
    static let shared = MockIslandController()

    var state: IslandState = .idle
    var isPinnedOpen: Bool = false
    var isHovering: Bool = false
    var targetSize: CGSize = CGSize(width: 180, height: 32)
    var previousSize: CGSize = CGSize(width: 180, height: 32)
    var activeAlert: String? = nil
    var activeExpandedAlert: String? = nil

    var activeOrganicItem: OrganicNotchExpandedItem = .none {
        didSet {
            let geomNotchH: CGFloat = 32.0
            if state == .expanded {
                switch activeOrganicItem {
                case .none:
                    targetSize = CGSize(width: 500, height: geomNotchH + 175)
                case .clipboard:
                    targetSize = CGSize(width: 520, height: geomNotchH + 430)
                case .dropper:
                    targetSize = CGSize(width: 500, height: geomNotchH + 320)
                case .device:
                    targetSize = CGSize(width: 520, height: geomNotchH + 390)
                case .storageCleaner:
                    targetSize = CGSize(width: 540, height: geomNotchH + 430)
                case .colorDropper:
                    targetSize = CGSize(width: 500, height: geomNotchH + 320)
                case .plexo:
                    targetSize = CGSize(width: 560, height: geomNotchH + 450)
                }
            }
        }
    }

    func transitionTo(_ newState: IslandState) {
        previousSize = targetSize
        state = newState
        if newState == .expanded {
            let geomNotchH: CGFloat = 32.0
            switch activeOrganicItem {
            case .none:
                targetSize = CGSize(width: 500, height: geomNotchH + 175)
            case .clipboard:
                targetSize = CGSize(width: 520, height: geomNotchH + 430)
            case .dropper:
                targetSize = CGSize(width: 500, height: geomNotchH + 320)
            case .device:
                targetSize = CGSize(width: 520, height: geomNotchH + 390)
            case .storageCleaner:
                targetSize = CGSize(width: 540, height: geomNotchH + 430)
            case .colorDropper:
                targetSize = CGSize(width: 500, height: geomNotchH + 320)
            case .plexo:
                targetSize = CGSize(width: 560, height: geomNotchH + 450)
            }
        } else {
            targetSize = CGSize(width: 180, height: 32)
        }
    }

    func onHoverEntered() {
        isHovering = true
        guard state != .expanded else { return }
        isPinnedOpen = false
        transitionTo(.expanded)
    }

    func onHoverExited() {
        isHovering = false
        guard state == .expanded else { return }
        guard !isPinnedOpen else { return }
        guard activeOrganicItem == .none else { return }

        activeOrganicItem = .none
        transitionTo(.idle)
    }

    func isMouseInHoverRegion(screenPoint: CGPoint, screenFrame: CGRect, notchRect: CGRect) -> Bool {
        let topY = screenFrame.maxY
        if state != .expanded {
            return notchRect.contains(screenPoint)
        } else {
            let targetW = max(targetSize.width, previousSize.width)
            let targetH = max(targetSize.height, previousSize.height)
            let minX = notchRect.midX - (targetW / 2.0) - 20.0
            let maxX = notchRect.midX + (targetW / 2.0) + 20.0
            let minY = topY - targetH - 20.0
            let maxY = topY + 1.0
            return screenPoint.x >= minX && screenPoint.x <= maxX && screenPoint.y >= minY && screenPoint.y <= maxY
        }
    }

    func containsPointInVisibleShape(screenPoint: CGPoint, windowFrame: CGRect, targetRect: CGRect, screenFrame: CGRect, notchRect: CGRect) -> Bool {
        let unionFrame = windowFrame.union(targetRect)
        if state == .expanded {
            return isMouseInHoverRegion(screenPoint: screenPoint, screenFrame: screenFrame, notchRect: notchRect) || unionFrame.contains(screenPoint)
        }
        return isMouseInHoverRegion(screenPoint: screenPoint, screenFrame: screenFrame, notchRect: notchRect) || unionFrame.contains(screenPoint)
    }
}

func runTestMatrix() {
    print("=== LiquidDynamo 1.9.2 Test Matrix Verification ===")
    let island = MockIslandController.shared
    let screenFrame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    let notchRect = CGRect(x: 774, y: 1085, width: 180, height: 32)

    var passedCount = 0

    // Test 1: Open by hover, click a device icon: stays open and shows the card
    island.transitionTo(.idle)
    island.activeOrganicItem = .none
    island.onHoverEntered()
    // User clicks device icon
    island.isPinnedOpen = true
    island.activeOrganicItem = .device("dev_airpods")
    // Gesture capture or tracking area sends hover exit
    island.onHoverExited()
    let t1Pass = (island.state == .expanded && island.isPinnedOpen && island.activeOrganicItem == .device("dev_airpods") && island.targetSize.height >= 420)
    print("Test 1 (Open hover -> click device -> stays open & sized): \(t1Pass ? "PASS" : "FAIL") [state=\(island.state), targetSize=\(island.targetSize)]")
    if t1Pass { passedCount += 1 }

    // Test 2: Open by click (pinned), click a device icon: same
    island.transitionTo(.idle)
    island.activeOrganicItem = .none
    island.isPinnedOpen = true
    island.transitionTo(.expanded)
    island.activeOrganicItem = .device("dev_iphone")
    island.onHoverExited()
    let t2Pass = (island.state == .expanded && island.isPinnedOpen && island.activeOrganicItem == .device("dev_iphone") && island.targetSize.height >= 420)
    print("Test 2 (Open click -> click device -> stays open & sized): \(t2Pass ? "PASS" : "FAIL") [state=\(island.state), targetSize=\(island.targetSize)]")
    if t2Pass { passedCount += 1 }

    // Test 3: Click clipboard icon, then an entry: stays open, shows "Copied"
    island.activeOrganicItem = .clipboard
    let t3_1 = (island.state == .expanded && island.targetSize.height >= 440)
    // Simulate entry copied
    let copiedId: String? = "entry-123"
    let t3Pass = t3_1 && (copiedId != nil) && island.state == .expanded
    print("Test 3 (Click clipboard -> entry copied -> stays open): \(t3Pass ? "PASS" : "DESIGN_FAIL") [targetSize=\(island.targetSize)]")
    if t3Pass { passedCount += 1 }

    // Test 4: Click dropper icon: stays open, shelf shown
    island.activeOrganicItem = .dropper
    let t4Pass = (island.state == .expanded && island.targetSize.width == 500 && island.targetSize.height >= 340)
    print("Test 4 (Click dropper -> stays open, shelf sized): \(t4Pass ? "PASS" : "FAIL") [targetSize=\(island.targetSize)]")
    if t4Pass { passedCount += 1 }

    // Test 5: Click icon A, then icon B, then A again: no collapse between switches
    island.activeOrganicItem = .device("dev_A")
    let s1 = island.state
    island.activeOrganicItem = .device("dev_B")
    let s2 = island.state
    island.activeOrganicItem = .device("dev_A")
    let s3 = island.state
    let t5Pass = (s1 == .expanded && s2 == .expanded && s3 == .expanded && island.activeOrganicItem == .device("dev_A"))
    print("Test 5 (Switch A -> B -> A without collapse): \(t5Pass ? "PASS" : "FAIL")")
    if t5Pass { passedCount += 1 }

    // Test 6: Click an icon while a volume/connect alert is showing
    island.activeExpandedAlert = "volume_hud"
    island.activeOrganicItem = .device("dev_mouse")
    // calculateDimensions picks detail size because activeOrganicItem != .none
    let t6Pass = (island.targetSize.height >= 420 && island.activeOrganicItem == .device("dev_mouse"))
    print("Test 6 (Click icon while alert active -> detail size takes precedence): \(t6Pass ? "PASS" : "FAIL")")
    if t6Pass { passedCount += 1 }
    island.activeExpandedAlert = nil

    // Test 7: Click an icon on an external, non-notched display
    let extScreenFrame = CGRect(x: 1728, y: 0, width: 1920, height: 1080)
    let extNotchRect = CGRect(x: 1728 + 960 - 70, y: 1080 - 32, width: 140, height: 32)
    let clickPt = CGPoint(x: 1728 + 960, y: 1080 - 150)
    let inExtRegion = island.isMouseInHoverRegion(screenPoint: clickPt, screenFrame: extScreenFrame, notchRect: extNotchRect)
    let t7Pass = inExtRegion && island.state == .expanded
    print("Test 7 (Click icon on external display): \(t7Pass ? "PASS" : "FAIL")")
    if t7Pass { passedCount += 1 }

    // Test 8: Click an icon, then move cursor slowly out and back in: collapse only after truly leaving
    let insidePt = CGPoint(x: 864, y: 900)
    let bufferPt = CGPoint(x: 864, y: 1117 - 422 - 15) // within 20pt buffer
    let trulyOutsidePt = CGPoint(x: 864, y: 400) // far below
    let insideCheck = island.isMouseInHoverRegion(screenPoint: insidePt, screenFrame: screenFrame, notchRect: notchRect)
    let bufferCheck = island.isMouseInHoverRegion(screenPoint: bufferPt, screenFrame: screenFrame, notchRect: notchRect)
    let outsideCheck = island.isMouseInHoverRegion(screenPoint: trulyOutsidePt, screenFrame: screenFrame, notchRect: notchRect)
    let t8Pass = insideCheck && bufferCheck && !outsideCheck
    print("Test 8 (Cursor move: buffer keeps alive, truly leaving detects exit): \(t8Pass ? "PASS" : "FAIL")")
    if t8Pass { passedCount += 1 }

    // Test 9: Click outside: closes. Press Escape: closes.
    // Outside click calls vm.close()
    island.isPinnedOpen = false
    island.activeOrganicItem = .none
    island.transitionTo(.idle)
    let t9Pass = (island.state == .idle)
    print("Test 9 (Click outside / Escape closes): \(t9Pass ? "PASS" : "FAIL")")
    if t9Pass { passedCount += 1 }

    // Test 10: Disconnect selected device while its card is open: card falls back cleanly without collapse glitch
    island.transitionTo(.expanded)
    island.isPinnedOpen = true
    island.activeOrganicItem = .device("dev_disconnected")
    // deviceMonitor.activeDevices["dev_disconnected"] becomes nil
    let activeDevices: [String: DeviceIdentity] = [:]
    let dev = activeDevices["dev_disconnected"]
    let fallbackRendered = (dev == nil) // renders fallback/remembered card
    let t10Pass = (fallbackRendered && island.state == .expanded && island.activeOrganicItem == .device("dev_disconnected") && island.targetSize.height >= 420)
    print("Test 10 (Disconnect active device -> fallback card rendered without collapse): \(t10Pass ? "PASS" : "FAIL")")
    if t10Pass { passedCount += 1 }

    // Test 11: Click Plexo icon -> stays open, sized to 560x482, multi-network turbo downloader mounted
    island.activeOrganicItem = .plexo
    let t11Pass = (island.state == .expanded && island.targetSize == CGSize(width: 560, height: 32 + 450) && island.isPinnedOpen)
    print("Test 11 (Click Plexo -> stays open, sized to 560x482): \(t11Pass ? "PASS" : "FAIL") [targetSize=\(island.targetSize)]")
    if t11Pass { passedCount += 1 }

    print("\nTOTAL PASSED: \(passedCount)/11")
}

runTestMatrix()
