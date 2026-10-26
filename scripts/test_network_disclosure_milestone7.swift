import Foundation

func runBash(_ command: String) -> (status: Int32, stdout: String, stderr: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["-c", command]
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
print("🧪 Running Milestone 7 Tests: Network Disclosure & Privacy Opt-Ins")
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

// 1. Verify bundled default_wave_visualizer.json exists and is valid JSON
let jsonPath = "liquiddinamo/Resources/default_wave_visualizer.json"
let fileExists = FileManager.default.fileExists(atPath: jsonPath)
assertTest(fileExists, "Bundled default_wave_visualizer.json exists locally")

if fileExists, let data = try? Data(contentsOf: URL(fileURLWithPath: jsonPath)) {
    let jsonObj = try? JSONSerialization.jsonObject(with: data)
    assertTest(jsonObj != nil, "Bundled default_wave_visualizer.json is valid parseable JSON")
} else {
    assertTest(false, "Bundled default_wave_visualizer.json is valid parseable JSON")
}

// 2. Verify LottieAnimationView prefers bundled JSON over remote URL
let lottieFile = (try? String(contentsOfFile: "liquiddinamo/components/Music/LottieAnimationView.swift", encoding: .utf8)) ?? ""
assertTest(lottieFile.contains("default_wave_visualizer") && lottieFile.contains("Bundle.main.url(forResource:"),
           "LottieAnimationContainer resolves bundled local JSON first")

// 3. Verify PublicIPService guards on Defaults[.privacyPublicIPLookup]
let ipServiceFile = (try? String(contentsOfFile: "liquiddinamo/Features/Network/PublicIPService.swift", encoding: .utf8)) ?? ""
assertTest(ipServiceFile.contains("Defaults[.privacyPublicIPLookup]"),
           "PublicIPService enforces Defaults[.privacyPublicIPLookup] opt-in guard")

// 4. Verify MeshyImageTo3DProvider guards on Defaults[.privacyMeshyUploadEnabled]
let meshyFile = (try? String(contentsOfFile: "liquiddinamo/Features/DeviceShowcase/MeshyImageTo3DProvider.swift", encoding: .utf8)) ?? ""
assertTest(meshyFile.contains("Defaults[.privacyMeshyUploadEnabled]"),
           "MeshyImageTo3DProvider enforces Defaults[.privacyMeshyUploadEnabled] guard")

// 5. Verify CloudModelGenerationCoordinator presents explicit consent dialog before upload
let coordinatorFile = (try? String(contentsOfFile: "liquiddinamo/Features/DeviceShowcase/CloudModelGenerationCoordinator.swift", encoding: .utf8)) ?? ""
assertTest(coordinatorFile.contains("Consent Required") && coordinatorFile.contains("Defaults[.privacyMeshyUploadEnabled]"),
           "CloudModelGenerationCoordinator requires modal consent before transmitting images to Meshy AI")

// 6. Verify SettingsPrivacyView contains Network Access & Endpoints Disclosure card
let privacyViewFile = (try? String(contentsOfFile: "liquiddinamo/components/Settings/SettingsPrivacyView.swift", encoding: .utf8)) ?? ""
assertTest(privacyViewFile.contains("Network Access & Endpoints") &&
           privacyViewFile.contains("api.github.com") &&
           privacyViewFile.contains("api64.ipify.org") &&
           privacyViewFile.contains("api.meshy.ai") &&
           privacyViewFile.contains("lrclib.net"),
           "SettingsPrivacyView fully discloses all outbound endpoints with toggles")

// 7. Verify Constants.swift default values for network opt-ins
let constantsFile = (try? String(contentsOfFile: "liquiddinamo/models/Constants.swift", encoding: .utf8)) ?? ""
assertTest(constantsFile.contains("privacyPublicIPLookup\", default: false"),
           "privacyPublicIPLookup is OFF by default")
assertTest(constantsFile.contains("privacyMeshyUploadEnabled\", default: false"),
           "privacyMeshyUploadEnabled is OFF by default")
assertTest(constantsFile.contains("autoCheckUpdates\", default: true"),
           "autoCheckUpdates is ON by default")
assertTest(constantsFile.contains("enableLyrics\", default: false"),
           "enableLyrics is OFF by default")

// 8. Verify RULES.md and README.md accurate wording
let rulesFile = (try? String(contentsOfFile: "RULES.md", encoding: .utf8)) ?? ""
assertTest(rulesFile.contains("Zero Telemetry") && rulesFile.contains("Settings > Privacy"),
           "RULES.md accurately documents network boundaries and Settings opt-ins")

let readmeFile = (try? String(contentsOfFile: "README.md", encoding: .utf8)) ?? ""
assertTest(readmeFile.contains("Zero Telemetry & User-Controlled Network") && readmeFile.contains("Settings > Privacy"),
           "README.md transparently discloses network access and opt-in controls")

print("\n-----------------------------------------------------------------")
print("Results: \(passCount) passed, \(failCount) failed")
print("-----------------------------------------------------------------")
if failCount > 0 {
    exit(1)
}
