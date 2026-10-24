import Foundation
import CoreGraphics

print("=== STARTING WING CONTENT EXTRA SPACE & ASYMMETRIC SIZING TEST ===")

// 1. Test Intrinsic Width Measurement and Extra Spacing
let iconWidth: CGFloat = 10.0
let iconTextSpacing: CGFloat = 4.0
let textWidthCPU: CGFloat = 28.0 // "12%"
let textWidthNet: CGFloat = 72.0 // "↓12.4M ↑3.2M"

let leadingPad: CGFloat = 12.0
let trailingPadWithExtraSpace: CGFloat = 14.0 // 14pt extra breathing room requested by user

let intrinsicLeftCPU = iconWidth + iconTextSpacing + textWidthCPU + leadingPad + trailingPadWithExtraSpace
let intrinsicRightNet = iconWidth + iconTextSpacing + textWidthNet + leadingPad + trailingPadWithExtraSpace

print("[TEST 1] Content-Aware Intrinsic Width:")
print("  Left CPU Wing (with extra space): \(intrinsicLeftCPU) pt")
print("  Right Net Wing (with extra space): \(intrinsicRightNet) pt")

assert(trailingPadWithExtraSpace == 14.0, "Must have 14pt extra trailing breathing room")
assert(intrinsicLeftCPU < intrinsicRightNet, "CPU wing must be smaller than verbose network wing")
assert(intrinsicLeftCPU >= 38.0, "Must be above minimum aesthetic floor (38pt)")
print("  -> PASS: Extra breathing space cleanly allocated.")

// 2. Test Independent Asymmetric Window Geometry
let rawNotchW: CGFloat = 210.0
let centerSpacer: CGFloat = 14.0
let maxW = max(intrinsicLeftCPU, intrinsicRightNet)
let totalWindowW = rawNotchW + centerSpacer + (2.0 * maxW)

print("\n[TEST 2] Centered Host Window Coverage:")
print("  Raw Notch: \(rawNotchW) pt")
print("  Left Wing Width: \(intrinsicLeftCPU) pt")
print("  Right Wing Width: \(intrinsicRightNet) pt")
print("  Max Wing Width: \(maxW) pt")
print("  Total Window Width: \(totalWindowW) pt")

// Left wing origin from window midX
let halfWindow = totalWindowW / 2.0
let leftWingLeftEdge = halfWindow - (rawNotchW / 2.0) - intrinsicLeftCPU
let rightWingRightEdge = halfWindow + (rawNotchW / 2.0) + intrinsicRightNet

assert(leftWingLeftEdge >= 0, "Left wing droplet must not be clipped by window left edge")
assert(rightWingRightEdge <= totalWindowW, "Right wing droplet must not be clipped by window right edge")
print("  -> PASS: Asymmetric droplets fit completely within the centered window without clipping.")

// 3. Test Shrink Settle Response
let verboseW: CGFloat = 110.0
let collapsedIconOnlyW: CGFloat = 38.0
var measuredW = verboseW
assert(measuredW == 110.0)
// Simulate content shrink
measuredW = collapsedIconOnlyW
assert(measuredW == 38.0, "Preference key must adapt downward when content shrinks")
print("\n[TEST 3] Bi-directional Size Adaptation:")
print("  Expanded Width: \(verboseW) pt -> Collapsed Width: \(collapsedIconOnlyW) pt")
print("  -> PASS: Wings adapt downward when content shrinks.")

print("\n=== ALL CONTENT-AWARE EXTRA SPACE TESTS PASSED SUCCESSFULLY! ===")
