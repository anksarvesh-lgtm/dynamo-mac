import Foundation

@main
struct TestRunner {
    static func main() {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path

        func testURL(_ relative: String) -> URL {
            URL(fileURLWithPath: "\(home)/\(relative)")
        }

        func evaluate(_ relative: String) -> DeletionSafetyDecision {
            StorageSafetyPolicy.evaluate(testURL(relative))
        }

        print("Running Purge Allowlist Safety Audit Tests...")

        // 1. Never delete system locations
        assert(StorageSafetyPolicy.evaluate(URL(fileURLWithPath: "/System")) == .blockedNeverDelete)
        assert(StorageSafetyPolicy.evaluate(URL(fileURLWithPath: "/usr/bin")) == .blockedNeverDelete)
        assert(StorageSafetyPolicy.evaluate(URL(fileURLWithPath: "/Library/Caches")) == .blockedNeverDelete)

        // 2. Protected daemons under ~/Library/Caches
        assert(evaluate("Library/Caches/CloudKit") == .blockedNeverDelete)
        assert(evaluate("Library/Caches/FamilyCircle") == .blockedNeverDelete)
        assert(evaluate("Library/Caches/com.apple.accountsd") == .blockedNeverDelete)
        assert(evaluate("Library/Caches/com.apple.akd") == .blockedNeverDelete)
        assert(evaluate("Library/Caches/PassKit") == .blockedNeverDelete)

        // 3. User roots & sensitive paths
        assert(evaluate("Library") == .blockedNeverDelete)
        assert(evaluate("Library/Keychains") == .blockedNeverDelete)
        assert(evaluate("Library/Preferences") == .blockedNeverDelete)
        assert(evaluate("Library/Mail") == .blockedNeverDelete)
        assert(evaluate("Desktop") == .blockedNeverDelete)
        assert(evaluate("Documents") == .blockedNeverDelete)
        assert(evaluate("Pictures") == .blockedNeverDelete)
        assert(evaluate("Music") == .blockedNeverDelete)

        // 4. Ruby gems protection
        assert(evaluate(".gem") != .allow)
        assert(evaluate(".gem/ruby/3.3.0/gems/cocoapods-1.16.2") != .allow)
        assert(evaluate(".gem/ruby/3.3.0/bin/pod") != .allow)
        assert(evaluate(".gem/specs") == .allow)
        assert(evaluate(".gem/ruby/3.3.0/cache") == .allow)

        // 5. JetBrains LocalHistory protection
        assert(evaluate("Library/Caches/JetBrains") == .blockedNeverDelete)
        assert(evaluate("Library/Caches/JetBrains/IntelliJIdea2025.2") == .blockedNeverDelete)
        assert(evaluate("Library/Caches/JetBrains/IntelliJIdea2025.2/LocalHistory") == .blockedNeverDelete)
        assert(evaluate("Library/Caches/JetBrains/IntelliJIdea2025.2/caches") == .allow)

        // 6. Zed database protection
        assert(evaluate("Library/Application Support/Zed/db") != .allow)
        assert(evaluate("Library/Caches/Zed") == .allow)

        // 7. Whitelisted build & cache directories
        assert(evaluate("Library/Caches/org.swift.swiftpm") == .allow)
        assert(evaluate("Library/Developer/Xcode/DerivedData") == .allow)
        assert(evaluate(".npm") == .allow)
        assert(evaluate(".yarn/cache") == .allow)
        assert(evaluate(".cargo/registry") == .allow)
        assert(evaluate("Library/Developer/CoreSimulator/Caches") == .allow)
        assert(evaluate("Library/Logs") == .allow)
        assert(evaluate("Library/Logs/DiagnosticReports") == .allow)
        assert(evaluate(".pub-cache/hosted") == .allow)
        assert(evaluate(".ollama/models") == .allow)
        assert(evaluate(".lmstudio/models") == .allow)
        assert(evaluate(".cache/huggingface/hub") == .allow)

        // 8. Substring safety counter-examples (dist-notes, rebuild-plan, building-app)
        // Must NOT be allowed by evaluate or marked safeToClean by safetyTier!
        assert(evaluate("Developer/dist-notes") != .allow)
        assert(evaluate("Developer/rebuild-plan") != .allow)
        assert(evaluate("Projects/building-app") != .allow)
        assert(StorageSafetyPolicy.safetyTier(for: testURL("Developer/dist-notes"), category: .developer) == .checkFirst)
        assert(StorageSafetyPolicy.safetyTier(for: testURL("Developer/rebuild-plan"), category: .developer) == .checkFirst)
        assert(StorageSafetyPolicy.safetyTier(for: testURL("Projects/building-app"), category: .developer) == .checkFirst)

        // 9. Verified real build outputs must be safeToClean
        assert(StorageSafetyPolicy.safetyTier(for: testURL("Library/Developer/Xcode/DerivedData/MyApp"), category: .developer) == .safeToClean)
        assert(StorageSafetyPolicy.safetyTier(for: testURL("Projects/MyApp/dist"), category: .developer) == .safeToClean)
        assert(StorageSafetyPolicy.safetyTier(for: testURL("Projects/MyApp/build"), category: .developer) == .safeToClean)

        print("✅ All Purge Allowlist Safety Audit Tests PASSED successfully!")
    }
}
