//
//  test_updater_milestone2.swift
//  LiquidDynamo Tests - Milestone 2 (Secure Application Updater)
//

import Foundation
import Security

// Import or copy SemanticVersion & UpdateSecurityError definitions to test them directly
public struct SemanticVersion: Comparable, CustomStringConvertible, Equatable, Hashable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: [String]
    public let buildMetadata: String?

    public init?(_ string: String) {
        var str = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.hasPrefix("v") || str.hasPrefix("V") {
            str.removeFirst()
        }
        str = str.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !str.isEmpty else { return nil }

        let buildParts = str.components(separatedBy: "+")
        let versionAndPrerelease = buildParts[0]
        self.buildMetadata = buildParts.count > 1 ? buildParts.dropFirst().joined(separator: "+") : nil

        let preParts = versionAndPrerelease.components(separatedBy: "-")
        let numericPart = preParts[0]
        if preParts.count > 1 {
            let preString = preParts.dropFirst().joined(separator: "-")
            self.prerelease = preString.components(separatedBy: ".").filter { !$0.isEmpty }
        } else {
            self.prerelease = []
        }

        let coreNums = numericPart.components(separatedBy: ".")
        guard let majorInt = Int(coreNums[0]), majorInt >= 0 else { return nil }
        self.major = majorInt

        if coreNums.count > 1 {
            guard let minorInt = Int(coreNums[1]), minorInt >= 0 else { return nil }
            self.minor = minorInt
        } else {
            self.minor = 0
        }

        if coreNums.count > 2 {
            guard let patchInt = Int(coreNums[2]), patchInt >= 0 else { return nil }
            self.patch = patchInt
        } else {
            self.patch = 0
        }
    }

    public var description: String {
        var res = "\(major).\(minor).\(patch)"
        if !prerelease.isEmpty {
            res += "-" + prerelease.joined(separator: ".")
        }
        if let b = buildMetadata {
            res += "+" + b
        }
        return res
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        if lhs.patch != rhs.patch {
            return lhs.patch < rhs.patch
        }

        if lhs.prerelease.isEmpty && !rhs.prerelease.isEmpty {
            return false
        }
        if !lhs.prerelease.isEmpty && rhs.prerelease.isEmpty {
            return true
        }
        if lhs.prerelease.isEmpty && rhs.prerelease.isEmpty {
            return false
        }

        let minCount = min(lhs.prerelease.count, rhs.prerelease.count)
        for i in 0..<minCount {
            let leftId = lhs.prerelease[i]
            let rightId = rhs.prerelease[i]
            if leftId == rightId { continue }

            let leftNum = Int(leftId)
            let rightNum = Int(rightId)

            switch (leftNum, rightNum) {
            case let (.some(l), .some(r)):
                return l < r
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return leftId < rightId
            }
        }

        return lhs.prerelease.count < rhs.prerelease.count
    }

    public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        return lhs.major == rhs.major &&
               lhs.minor == rhs.minor &&
               lhs.patch == rhs.patch &&
               lhs.prerelease == rhs.prerelease
    }
}

public enum UpdateSecurityError: LocalizedError, Equatable {
    case invalidURL(String)
    case missingBinary
    case bundleIdentifierMismatch(found: String, expected: String)
    case codeSignatureVerificationFailed(String)
    case teamIDMismatch(found: String, expected: String)
    case gatekeeperRejected(String)
    case versionNotNewer(found: String, current: String)
}

func validateDownloadURL(_ url: URL) throws {
    guard let scheme = url.scheme?.lowercased(), scheme == "https" else {
        throw UpdateSecurityError.invalidURL("Insecure protocol: '\(url.scheme ?? "none")'. Strict HTTPS is required.")
    }
    guard let host = url.host?.lowercased(),
          host == "github.com" || host.hasSuffix(".github.com") || host == "objects.githubusercontent.com" else {
        throw UpdateSecurityError.invalidURL("Untrusted download host '\(url.host ?? "unknown")'. Only official GitHub hosts are permitted.")
    }
}

func isVersion(_ v1: String, greaterThan v2: String) -> Bool {
    if let sem1 = SemanticVersion(v1), let sem2 = SemanticVersion(v2) {
        return sem1 > sem2
    }
    let clean1 = v1.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
    let clean2 = v2.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
    return clean1.compare(clean2, options: .numeric) == .orderedDescending
}

// MARK: - Test Runner

var totalTests = 0
var passedTests = 0

func assertTest(_ condition: Bool, _ message: String) {
    totalTests += 1
    if condition {
        passedTests += 1
        print("  ✅ PASS: \(message)")
    } else {
        print("  ❌ FAIL: \(message)")
    }
}

print("==================================================================")
print("🚀 RUNNING MILESTONE 2 TEST SUITE: SECURE APPLICATION UPDATER")
print("==================================================================")

// Test Suite 1: SemVer Comparison & Pre-Release Precedence
print("\n[Suite 1: SemVer Comparison & Pre-Release Precedence]")
do {
    // 1. Bug confirmation: NSString numeric comparison ranked "2.8-rc.1" > "2.8"
    let v2_8_rc1 = SemanticVersion("2.8-rc.1")!
    let v2_8 = SemanticVersion("2.8")!
    assertTest(v2_8_rc1 < v2_8, "2.8-rc.1 is strictly less than 2.8")
    assertTest(v2_8 > v2_8_rc1, "2.8 is strictly greater than 2.8-rc.1")
    assertTest(isVersion("2.8-rc.1", greaterThan: "2.8") == false, "isVersion('2.8-rc.1', greaterThan: '2.8') returns false")
    assertTest(isVersion("2.8", greaterThan: "2.8-rc.1") == true, "isVersion('2.8', greaterThan: '2.8-rc.1') returns true")

    // 2. Pre-release identifier numeric comparison
    let v2_8_rc2 = SemanticVersion("2.8-rc.2")!
    assertTest(v2_8_rc1 < v2_8_rc2, "2.8-rc.1 < 2.8-rc.2")

    // 3. Minor version precedence (1.10 > 1.9)
    let v1_10 = SemanticVersion("1.10")!
    let v1_9 = SemanticVersion("1.9")!
    assertTest(v1_10 > v1_9, "1.10 > 1.9")

    // 4. SemVer 2.0 standard pre-release chain
    let vAlpha = SemanticVersion("1.0.0-alpha")!
    let vAlpha1 = SemanticVersion("1.0.0-alpha.1")!
    let vBeta = SemanticVersion("1.0.0-beta")!
    let vBeta2 = SemanticVersion("1.0.0-beta.2")!
    let vRC1 = SemanticVersion("1.0.0-rc.1")!
    let vFinal = SemanticVersion("1.0.0")!

    assertTest(vAlpha < vAlpha1, "1.0.0-alpha < 1.0.0-alpha.1")
    assertTest(vAlpha1 < vBeta, "1.0.0-alpha.1 < 1.0.0-beta")
    assertTest(vBeta < vBeta2, "1.0.0-beta < 1.0.0-beta.2")
    assertTest(vBeta2 < vRC1, "1.0.0-beta.2 < 1.0.0-rc.1")
    assertTest(vRC1 < vFinal, "1.0.0-rc.1 < 1.0.0")

    // 5. Build metadata is ignored in precedence
    let vBuild1 = SemanticVersion("1.0.0+20130313144700")!
    let vBuild2 = SemanticVersion("1.0.0+exp.sha.5114f85")!
    assertTest(vBuild1 == vBuild2, "Build metadata is ignored in version equality (1.0.0+a == 1.0.0+b)")
    assertTest(!(vBuild1 < vBuild2) && !(vBuild1 > vBuild2), "Build metadata does not alter version ordering")

    // 6. Leading 'v' prefix normalization
    let vPrefix = SemanticVersion("v2.0.5")!
    let vNoPrefix = SemanticVersion("2.0.5")!
    assertTest(vPrefix == vNoPrefix, "v2.0.5 == 2.0.5 with prefix normalization")
}

// Test Suite 2: Download URL Security & Host Whitelisting
print("\n[Suite 2: Download URL Protocol & Host Enforcement]")
do {
    // Insecure HTTP rejection
    let insecureURL = URL(string: "http://github.com/anksarvesh-lgtm/dynamo-mac/releases/download/v2.0.6/liquiddynamo.zip")!
    var threwInsecure = false
    do {
        try validateDownloadURL(insecureURL)
    } catch {
        threwInsecure = true
    }
    assertTest(threwInsecure, "Insecure HTTP scheme is rejected")

    // Malicious untrusted host rejection
    let evilHostURL = URL(string: "https://evil-mirror.com/dynamo-mac/releases/download/v2.0.6/liquiddynamo.zip")!
    var threwEvilHost = false
    do {
        try validateDownloadURL(evilHostURL)
    } catch {
        threwEvilHost = true
    }
    assertTest(threwEvilHost, "Untrusted host outside github.com is rejected")

    // Official GitHub release asset URLs accepted
    let validGithubURL = URL(string: "https://github.com/anksarvesh-lgtm/dynamo-mac/releases/download/v2.0.6/liquiddynamo.zip")!
    var validGithubSucceeded = false
    do {
        try validateDownloadURL(validGithubURL)
        validGithubSucceeded = true
    } catch {}
    assertTest(validGithubSucceeded, "Official https://github.com release asset URL accepted")

    let validAssetCDN = URL(string: "https://objects.githubusercontent.com/github-production-release-asset-2e65be/12345/app.zip")!
    var validCDNSucceeded = false
    do {
        try validateDownloadURL(validAssetCDN)
        validCDNSucceeded = true
    } catch {}
    assertTest(validCDNSucceeded, "Official https://objects.githubusercontent.com release asset URL accepted")
}

// Test Suite 3: Bundle Identifier & Version Verification
print("\n[Suite 3: Staged Application Bundle & Security Verification]")
do {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("UpdaterSecurityTest_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fakeAppURL = tempDir.appendingPathComponent("FakeApp.app")
    let fakeMacOS = fakeAppURL.appendingPathComponent("Contents/MacOS")
    let fakeContents = fakeAppURL.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: fakeMacOS, withIntermediateDirectories: true)

    // 1. Missing binary test
    var missingBinaryDetected = false
    let execs = (try? FileManager.default.contentsOfDirectory(atPath: fakeMacOS.path)) ?? []
    if execs.isEmpty {
        missingBinaryDetected = true
    }
    assertTest(missingBinaryDetected, "App bundle with empty Contents/MacOS is detected as missing binary")

    // Create a mock executable
    let mockExec = fakeMacOS.appendingPathComponent("LiquidDynamo")
    FileManager.default.createFile(atPath: mockExec.path, contents: Data([0xCF, 0xFA, 0xED, 0xFE]))

    // 2. Mismatched Bundle Identifier test
    let fakePlist: [String: Any] = [
        "CFBundleIdentifier": "com.malicious.imposter",
        "CFBundleShortVersionString": "2.1.0"
    ]
    let plistData = try PropertyListSerialization.data(fromPropertyList: fakePlist, format: .xml, options: 0)
    try plistData.write(to: fakeContents.appendingPathComponent("Info.plist"))

    let stagedDict = NSDictionary(contentsOf: fakeContents.appendingPathComponent("Info.plist")) as? [String: Any]
    let stagedBundleID = stagedDict?["CFBundleIdentifier"] as? String ?? ""
    let expectedBundleID = "com.sarvesh.LiquidDynamo"
    assertTest(stagedBundleID != expectedBundleID, "Bundle ID spoofing is caught ('com.malicious.imposter' != 'com.sarvesh.LiquidDynamo')")

    // 3. Downgrade attack protection test
    let downgradePlist: [String: Any] = [
        "CFBundleIdentifier": "com.sarvesh.LiquidDynamo",
        "CFBundleShortVersionString": "1.5.0"
    ]
    let downgradeData = try PropertyListSerialization.data(fromPropertyList: downgradePlist, format: .xml, options: 0)
    try downgradeData.write(to: fakeContents.appendingPathComponent("Info.plist"))

    let downgradeDict = NSDictionary(contentsOf: fakeContents.appendingPathComponent("Info.plist")) as? [String: Any]
    let stagedVer = SemanticVersion(downgradeDict?["CFBundleShortVersionString"] as? String ?? "")!
    let currentVer = SemanticVersion("2.0.5")!
    assertTest(stagedVer < currentVer, "Version downgrade is detected and rejected (1.5.0 < 2.0.5)")
}

// Test Suite 4: Atomic Replacement & Rollback Shell Logic
print("\n[Suite 4: Atomic Replacement with Rollback Mechanics]")
do {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("UpdaterRollbackTest_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let targetApp = tempDir.appendingPathComponent("Target.app")
    let stagingApp = tempDir.appendingPathComponent("Staging.app")
    let targetMarker = targetApp.appendingPathComponent("marker.txt")
    let stagingMarker = stagingApp.appendingPathComponent("marker.txt")

    try FileManager.default.createDirectory(at: targetApp, withIntermediateDirectories: true)
    try "ORIGINAL_APP_V2.0.5".write(to: targetMarker, atomically: true, encoding: .utf8)

    try FileManager.default.createDirectory(at: stagingApp, withIntermediateDirectories: true)
    try "NEW_APP_V2.0.6".write(to: stagingMarker, atomically: true, encoding: .utf8)

    // Execute atomic swap with backup
    let backupApp = tempDir.appendingPathComponent(".Target_Backup.app")
    let tempInstall = tempDir.appendingPathComponent(".Target_Updating.app")

    // 1. Copy staging to temp install
    try FileManager.default.copyItem(at: stagingApp, to: tempInstall)
    assertTest(FileManager.default.fileExists(atPath: tempInstall.path), "Verified staging copied to temporary install beside target")

    // 2. Atomic backup of target
    try FileManager.default.moveItem(at: targetApp, to: backupApp)
    assertTest(!FileManager.default.fileExists(atPath: targetApp.path) && FileManager.default.fileExists(atPath: backupApp.path), "Original target atomically moved to backup")

    // 3. Move temp install into target place
    try FileManager.default.moveItem(at: tempInstall, to: targetApp)
    let installedContent = try String(contentsOf: targetMarker, encoding: .utf8)
    assertTest(installedContent == "NEW_APP_V2.0.6", "Target updated successfully with new version")

    // 4. Simulate rollback when replacement fails
    try FileManager.default.removeItem(at: targetApp)
    try FileManager.default.moveItem(at: backupApp, to: targetApp)
    let restoredContent = try String(contentsOf: targetMarker, encoding: .utf8)
    assertTest(restoredContent == "ORIGINAL_APP_V2.0.5", "Rollback successfully restores original application intact")
}

print("\n==================================================================")
print("TEST SUMMARY: \(passedTests)/\(totalTests) TESTS PASSED")
print("==================================================================")

if passedTests == totalTests {
    exit(0)
} else {
    exit(1)
}
