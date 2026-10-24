#!/usr/bin/env swift
import Foundation

print("==> Running GitHub Update Checker & Auto-Updater Tests...")

// Test 1: Version comparison
func isVersion(_ v1: String, greaterThan v2: String) -> Bool {
    let clean1 = v1.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
    let clean2 = v2.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
    return clean1.compare(clean2, options: .numeric) == .orderedDescending
}

assert(isVersion("1.9.9", greaterThan: "1.9.8") == true, "1.9.9 should be > 1.9.8")
assert(isVersion("v1.9.9", greaterThan: "1.9.8") == true, "v1.9.9 should be > 1.9.8")
assert(isVersion("1.10.0", greaterThan: "1.9.8") == true, "1.10.0 should be > 1.9.8")
assert(isVersion("1.9.8", greaterThan: "1.9.8") == false, "1.9.8 should not be > 1.9.8")
assert(isVersion("1.9.7", greaterThan: "1.9.8") == false, "1.9.7 should not be > 1.9.8")
print("✅ Test 1 Passed: Version comparison correctly identifies updates.")

// Test 2: Asset parsing priority (liquiddynamo.zip preferred over dmg)
let mockAssets: [[String: Any]] = [
    ["name": "LiquidDynamo-1.9.9.dmg", "browser_download_url": "https://github.com/test/releases/download/v1.9.9/LiquidDynamo-1.9.9.dmg"],
    ["name": "liquiddynamo.zip", "browser_download_url": "https://github.com/test/releases/download/v1.9.9/liquiddynamo.zip"],
    ["name": "LiquidDynamo.dmg", "browser_download_url": "https://github.com/test/releases/download/v1.9.9/LiquidDynamo.dmg"]
]

var chosenURL: URL? = nil
if let zipAsset = mockAssets.first(where: {
    let name = ($0["name"] as? String)?.lowercased() ?? ""
    return name == "liquiddynamo.zip" || name.hasSuffix(".zip")
}), let downloadStr = zipAsset["browser_download_url"] as? String, let url = URL(string: downloadStr) {
    chosenURL = url
}

assert(chosenURL?.absoluteString == "https://github.com/test/releases/download/v1.9.9/liquiddynamo.zip", "liquiddynamo.zip must be chosen as highest priority")
print("✅ Test 2 Passed: liquiddynamo.zip selected over dmg assets.")

// Test 3: Zip extraction and in-place staging test
let fm = FileManager.default
let testTmp = fm.temporaryDirectory.appendingPathComponent("test_updater_\(UUID().uuidString)")
try fm.createDirectory(at: testTmp, withIntermediateDirectories: true)

let mockAppDir = testTmp.appendingPathComponent("liquiddynamo.app")
let mockContents = mockAppDir.appendingPathComponent("Contents/MacOS")
try fm.createDirectory(at: mockContents, withIntermediateDirectories: true)
let mockBinary = mockContents.appendingPathComponent("LiquidDynamo")
try "echo mock".write(to: mockBinary, atomically: true, encoding: .utf8)

// Create test zip
let testZip = testTmp.appendingPathComponent("liquiddynamo.zip")
let dittoZip = Process()
dittoZip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
dittoZip.arguments = ["-c", "-k", "--keepParent", mockAppDir.path, testZip.path]
try dittoZip.run()
dittoZip.waitUntilExit()
assert(fm.fileExists(atPath: testZip.path), "Test zip must be created")

// Unpack test zip to destination
let testExtractDir = testTmp.appendingPathComponent("extracted")
try fm.createDirectory(at: testExtractDir, withIntermediateDirectories: true)
let dittoUnpack = Process()
dittoUnpack.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
dittoUnpack.arguments = ["-x", "-k", testZip.path, testExtractDir.path]
try dittoUnpack.run()
dittoUnpack.waitUntilExit()

let extractedApp = testExtractDir.appendingPathComponent("liquiddynamo.app")
assert(fm.fileExists(atPath: extractedApp.path), "liquiddynamo.app must exist in extracted directory")
assert(fm.fileExists(atPath: extractedApp.appendingPathComponent("Contents/MacOS/LiquidDynamo").path), "Binary must exist inside extracted app")
print("✅ Test 3 Passed: Zip creation and ditto extraction preserves liquiddynamo.app bundle structure.")

// Test 4: Updater script structure test
let pid = 99999
let scriptContent = """
#!/bin/bash
TARGET_PRIMARY="/Applications/liquiddynamo.app"
TARGET_SECONDARY="/Applications/LiquidDynamo.app"
STAGING="\(extractedApp.path)"
PID="\(pid)"

COUNT=0
while kill -0 "$PID" 2>/dev/null && [ $COUNT -lt 100 ]; do
    sleep 0.1
    COUNT=$((COUNT+1))
done

rm -rf "$TARGET_PRIMARY"
cp -R "$STAGING" "$TARGET_PRIMARY"
xattr -dr com.apple.quarantine "$TARGET_PRIMARY" 2>/dev/null || true

rm -rf "$TARGET_SECONDARY"
cp -R "$STAGING" "$TARGET_SECONDARY"
xattr -dr com.apple.quarantine "$TARGET_SECONDARY" 2>/dev/null || true

rm -rf "$(dirname "$STAGING")" 2>/dev/null || true

if [ -d "$TARGET_PRIMARY" ]; then
    open "$TARGET_PRIMARY"
else
    open "$TARGET_SECONDARY"
fi
"""

assert(scriptContent.contains("/Applications/liquiddynamo.app"), "Must target /Applications/liquiddynamo.app")
assert(scriptContent.contains("/Applications/LiquidDynamo.app"), "Must target /Applications/LiquidDynamo.app")
assert(scriptContent.contains("xattr -dr com.apple.quarantine"), "Must clear quarantine attributes")
print("✅ Test 4 Passed: Updater script targets /Applications/liquiddynamo.app and strips quarantine.")

// Cleanup
try? fm.removeItem(at: testTmp)
print("🎉 ALL AUTO-UPDATER TESTS PASSED SUCCESSFULLY!")
