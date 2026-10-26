import Foundation

func runBash(_ command: String, env: [String: String] = [:]) -> (status: Int32, stdout: String, stderr: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["-c", command]
    
    var environment = ProcessInfo.processInfo.environment
    for (k, v) in env {
        environment[k] = v
    }
    process.environment = environment
    
    let outPipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe
    
    do {
        try process.run()
        process.waitUntilExit()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus,
                String(data: outData, encoding: .utf8) ?? "",
                String(data: errData, encoding: .utf8) ?? "")
    } catch {
        return (-1, "", error.localizedDescription)
    }
}

print("=================================================================")
print("🧪 Running Milestone 6 Tests: Release Script Reproducibility")
print("=================================================================")

var passCount = 0
var failCount = 0

func assertTest(_ condition: Bool, _ name: String, _ details: String = "") {
    if condition {
        print("  ✓ PASS: \(name)")
        passCount += 1
    } else {
        print("  ✗ FAIL: \(name) - \(details)")
        failCount += 1
    }
}

// 1. Verify build_dmg.sh syntax with bash -n
let syntaxRes = runBash("bash -n build_dmg.sh")
assertTest(syntaxRes.status == 0, "build_dmg.sh syntax is valid", syntaxRes.stderr)

// 2. Verify scripts/compile_dynamo.sh syntax with bash -n
let compileSyntax = runBash("bash -n scripts/compile_dynamo.sh")
assertTest(compileSyntax.status == 0, "scripts/compile_dynamo.sh syntax is valid", compileSyntax.stderr)

// 3. Verify scripts/setup_spm_deps.sh syntax with bash -n
let spmSyntax = runBash("bash -n scripts/setup_spm_deps.sh")
assertTest(spmSyntax.status == 0, "scripts/setup_spm_deps.sh syntax is valid", spmSyntax.stderr)

// 4. Verify scripts/verify_release.sh syntax with bash -n
let verifySyntax = runBash("bash -n scripts/verify_release.sh")
assertTest(verifySyntax.status == 0, "scripts/verify_release.sh syntax is valid", verifySyntax.stderr)

// 5. Release mode refuses missing signing identity
let noSignRes = runBash("bash build_dmg.sh", env: ["RELEASE": "1", "SIGN_IDENTITY": "-"])
assertTest(noSignRes.status != 0 && (noSignRes.stderr.contains("RELEASE REFUSED") || noSignRes.stdout.contains("RELEASE REFUSED")),
           "Release mode refuses missing Developer ID certificate",
           "Output: \(noSignRes.stdout)\n\(noSignRes.stderr)")

// 6. Release mode refuses non-Xcode fallback
// Simulate by shadowing xcodebuild with a failing stub in a temporary bin dir
let tempBinDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mock_bin_\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: tempBinDir, withIntermediateDirectories: true)
let mockXcodeBuild = tempBinDir.appendingPathComponent("xcodebuild")
try? "#!/bin/sh\nexit 1\n".write(to: mockXcodeBuild, atomically: true, encoding: .utf8)
_ = runBash("chmod +x '\(mockXcodeBuild.path)'")

let noXcodeRes = runBash("PATH='\(tempBinDir.path)':$PATH bash build_dmg.sh", env: [
    "RELEASE": "1",
    "SIGN_IDENTITY": "Developer ID Application: Fake (ABC1234567)"
])
try? FileManager.default.removeItem(at: tempBinDir)
assertTest(noXcodeRes.status != 0 && (noXcodeRes.stderr.contains("xcodebuild is not available") || noXcodeRes.stdout.contains("xcodebuild is not available")),
           "Release mode refuses non-Xcode fallback when xcodebuild is unavailable",
           "Output: \(noXcodeRes.stdout)\n\(noXcodeRes.stderr)")

// 7. Verify build number extraction matches project.pbxproj (CURRENT_PROJECT_VERSION)
let buildNumRes = runBash("grep -m1 'CURRENT_PROJECT_VERSION' LiquidDynamo.xcodeproj/project.pbxproj | awk -F'=' '{print $2}' | tr -d ' ;\\\"'")
let expectedBuildNum = buildNumRes.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
assertTest(expectedBuildNum == "18", "Project has CURRENT_PROJECT_VERSION 18", "Got: \(expectedBuildNum)")

// 8. Verify build_dmg.sh no longer hardcodes 'CFBundleVersion 17'
let hardcodedRes = runBash("grep 'CFBundleVersion -string \"17\"' build_dmg.sh")
assertTest(hardcodedRes.status != 0, "Hardcoded CFBundleVersion '17' removed from build_dmg.sh")

// 9. Verify dynamic SPM_DEPS_DIR with mktemp in compile_dynamo.sh
let mktempCompileRes = runBash("grep 'mktemp -d' scripts/compile_dynamo.sh")
assertTest(mktempCompileRes.status == 0, "scripts/compile_dynamo.sh uses mktemp -d for isolation")

// 10. Verify dynamic SPM_DEPS_DIR with mktemp in setup_spm_deps.sh
let mktempSpmRes = runBash("grep 'mktemp -d' scripts/setup_spm_deps.sh")
assertTest(mktempSpmRes.status == 0, "scripts/setup_spm_deps.sh uses mktemp -d for isolation")

print("\n-----------------------------------------------------------------")
print("Results: \(passCount) passed, \(failCount) failed")
print("-----------------------------------------------------------------")
if failCount > 0 {
    exit(1)
}
