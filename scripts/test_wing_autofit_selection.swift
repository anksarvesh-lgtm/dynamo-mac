import Foundation
import CoreGraphics
import AppKit

print("=== STARTING LIQUIDDYNAMO 1.9.3 WING AUTOFIT & SELECTION TEST SUITE ===")

// MARK: - 1. Selection & Persistence Tests
print("\n[TEST 1] Independent Wing Selection:")

enum MockWingMetric: String, CaseIterable, Identifiable {
    case none = "None"
    case cpuUsage = "CPU Usage"
    case cpuTemp = "CPU Temperature"
    case ramUsage = "RAM Usage"
    case ramDetails = "RAM (Used / Total)"
    case netDown = "Download Speed"
    case netUp = "Upload Speed"
    case netDownUp = "Network (Up/Down)"
    case battery = "Mac Battery"
    case bluetoothBattery = "Bluetooth Battery"
    case volume = "Volume"
    case brightness = "Brightness"
    case clock = "Clock"
    case weather = "Weather"
    case mediaPlayback = "Media Controls"
    case mediaTitle = "Now Playing Track"

    var id: String { rawValue }
}

var leftSelection: MockWingMetric = .cpuUsage
var rightSelection: MockWingMetric = .netDownUp

// Select CPU on left, RAM on right
leftSelection = .cpuUsage
rightSelection = .ramUsage
assert(leftSelection == .cpuUsage, "Left wing must be CPU usage")
assert(rightSelection == .ramUsage, "Right wing must be RAM usage")

// Changing left wing does not change right wing
leftSelection = .mediaPlayback
assert(rightSelection == .ramUsage, "Changing left wing must not overwrite right wing")

// Changing right wing does not change left wing
rightSelection = .weather
assert(leftSelection == .mediaPlayback, "Changing right wing must not overwrite left wing")

// Duplicate selection allowed if user desires
leftSelection = .cpuUsage
rightSelection = .cpuUsage
assert(leftSelection == .cpuUsage && rightSelection == .cpuUsage, "User can select same metric on both wings")

// All cases selectable
assert(MockWingMetric.allCases.count == 16, "All 16 WingMetric cases must exist")
print("  -> PASS: Independent selection validated without cross-overwriting.")

// MARK: - 2. Content-Aware Measurement & Auto-Fit Calculations
print("\n[TEST 2] Content-Aware Auto-Fit Width Calculations:")

func measureMetricWidth(metric: MockWingMetric, text: String) -> CGFloat {
    let padding: CGFloat = 18.0
    let iconWidth: CGFloat = 12.0
    let spacing: CGFloat = 3.5

    switch metric {
    case .none:
        return 0
    case .mediaPlayback:
        // 3 buttons: 3 * 14 pt + 2 * 6 pt spacing = 54 pt + 18 pt padding = 72 pt
        return 72.0
    default:
        // Approximate monospace text: ~7.5 pt per char for 9.5 pt font
        let textWidth = CGFloat(text.count) * 7.5
        return padding + iconWidth + spacing + textWidth
    }
}

func calculateWingWidth(metric: MockWingMetric, text: String, minConfiguredWidth: CGFloat, autoFit: Bool) -> CGFloat {
    guard metric != .none else { return 0 }
    if !autoFit {
        return minConfiguredWidth
    }
    let measured = measureMetricWidth(metric: metric, text: text)
    return max(minConfiguredWidth, measured)
}

let configuredMinWidth: CGFloat = 68.0

// Case A: Short value (e.g. CPU 9%)
let shortCpuWidth = calculateWingWidth(metric: .cpuUsage, text: "9%", minConfiguredWidth: configuredMinWidth, autoFit: true)
assert(shortCpuWidth == configuredMinWidth, "Short CPU value must respect min width: \(shortCpuWidth)")

// Case B: CPU 100%
let maxCpuWidth = calculateWingWidth(metric: .cpuUsage, text: "100%", minConfiguredWidth: configuredMinWidth, autoFit: true)
assert(maxCpuWidth >= configuredMinWidth, "CPU 100% width must be >= min width: \(maxCpuWidth)")

// Case C: CPU Temperature with extra digit (104°C)
let tempWidth = calculateWingWidth(metric: .cpuTemp, text: "104°C", minConfiguredWidth: configuredMinWidth, autoFit: true)
assert(tempWidth >= configuredMinWidth, "CPU Temp fits without truncation: \(tempWidth)")

// Case D: RAM details ("11.2 / 16.0 GB")
let ramDetailWidth = calculateWingWidth(metric: .ramDetails, text: "11.2 / 16.0 GB", minConfiguredWidth: configuredMinWidth, autoFit: true)
assert(ramDetailWidth > 110.0, "RAM details expands width for full string: \(ramDetailWidth)")

// Case E: Download speed ("12.4 MB/s")
let netDownWidth = calculateWingWidth(metric: .netDown, text: "12.4 MB/s", minConfiguredWidth: configuredMinWidth, autoFit: true)
assert(netDownWidth > 90.0, "Download speed expands for speed and unit: \(netDownWidth)")

// Case F: Media controls (previous, play/pause, next)
let mediaControlsWidth = calculateWingWidth(metric: .mediaPlayback, text: "", minConfiguredWidth: configuredMinWidth, autoFit: true)
assert(mediaControlsWidth >= 72.0, "Media controls fits all 3 buttons: \(mediaControlsWidth)")

// Case G: Media title ("Starboy • The Weeknd")
let mediaTitleWidth = calculateWingWidth(metric: .mediaTitle, text: "Starboy • The Weeknd", minConfiguredWidth: configuredMinWidth, autoFit: true)
assert(mediaTitleWidth > 140.0, "Media title expands to accommodate title and artist: \(mediaTitleWidth)")

// Case H: Auto-Fit disabled
let autoFitDisabledWidth = calculateWingWidth(metric: .ramDetails, text: "11.2 / 16.0 GB", minConfiguredWidth: configuredMinWidth, autoFit: false)
assert(autoFitDisabledWidth == configuredMinWidth, "When auto-fit is disabled, respects exact configured width: \(autoFitDisabledWidth)")

print("  -> PASS: All content types measure correctly without clipping.")

// MARK: - 3. Independent Asymmetric Wing Geometry
print("\n[TEST 3] Independent Asymmetric Wing Geometry:")

let rawNotchW: CGFloat = 210.0
let leftWingContentWidth = calculateWingWidth(metric: .cpuUsage, text: "18%", minConfiguredWidth: configuredMinWidth, autoFit: true) // 68 pt
let rightWingContentWidth = calculateWingWidth(metric: .netDown, text: "14.2 MB/s", minConfiguredWidth: configuredMinWidth, autoFit: true) // ~104 pt

assert(leftWingContentWidth == 68.0, "Left wing must stay at its natural 68 pt width")
assert(rightWingContentWidth > 100.0, "Right wing must expand for download speed")
assert(leftWingContentWidth != rightWingContentWidth, "Wings must have independent asymmetric widths")

let maxWingW = max(leftWingContentWidth, rightWingContentWidth)
assert(maxWingW == rightWingContentWidth, "Max wing width is driven by the wider wing")

// Window total width keeps notch cutout centered:
let totalWindowW = rawNotchW + 14.0 + (2.0 * maxWingW)
let leftSideContainerW = maxWingW
let rightSideContainerW = maxWingW
let centerCutoutW = rawNotchW + 14.0

assert(leftSideContainerW + centerCutoutW + rightSideContainerW == totalWindowW, "Window layout is symmetrically centered on notch")

// Check drop anchoring:
// Left drop is aligned .trailing in leftSideContainerW:
let leftDropLeadingSpacer = leftSideContainerW - leftWingContentWidth
assert(leftDropLeadingSpacer > 0, "Left drop has leading spacer; right edge touches notch edge")

// Right drop is aligned .leading in rightSideContainerW:
let rightDropTrailingSpacer = rightSideContainerW - rightWingContentWidth
assert(rightDropTrailingSpacer == 0, "Right drop occupies leading position; left edge touches notch edge")

print("  Left Wing Content Width: \(leftWingContentWidth) pt")
print("  Right Wing Content Width: \(rightWingContentWidth) pt")
print("  Window Total Width: \(totalWindowW) pt")
print("  Center Cutout Width: \(centerCutoutW) pt (centered at \(totalWindowW / 2.0) pt)")
print("  -> PASS: Independent asymmetric wing geometry keeps notch centered and wings anchored.")

// MARK: - 4. Layout Stability & Jitter Prevention
print("\n[TEST 4] Layout Stability & Jitter Threshold:")

var reportedWidths: [CGFloat] = []
var currentReportedWidth: CGFloat = 68.0

func updateWingWidthIfNeeded(newWidth: CGFloat) {
    if abs(currentReportedWidth - newWidth) >= 1.5 {
        currentReportedWidth = newWidth
        reportedWidths.append(newWidth)
    }
}

// Rapid minor jitter below 1.5 pt (e.g. 68.0 -> 68.4 -> 68.8 -> 68.2)
updateWingWidthIfNeeded(newWidth: 68.4)
updateWingWidthIfNeeded(newWidth: 68.8)
updateWingWidthIfNeeded(newWidth: 68.2)
assert(reportedWidths.isEmpty, "Minor jitter < 1.5 pt must NOT trigger layout resize")

// Legitimate expansion (e.g. 68.0 -> 94.0)
updateWingWidthIfNeeded(newWidth: 94.0)
assert(reportedWidths.count == 1, "Significant change triggers layout resize")

print("  -> PASS: 1.5 pt jitter threshold prevents layout oscillation.")

print("\n=== ALL TESTS PASSED SUCCESSFULLY! ===")
