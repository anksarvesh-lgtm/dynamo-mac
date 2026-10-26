//
//  StorageSafetyPolicy.swift
//  LiquidDynamo
//
//  Strict allow / deny safety policy gating all storage cleanup operations (Scopa Engine).
//  Protects macOS system directories, cloud sync daemons, identity keychain files,
//  running application state, and uncommitted git repositories.
//

import Foundation

public enum DeletionSafetyDecision: Equatable, Sendable {
    case allow
    case blockedNeverDelete
    case blockedNotWhitelisted

    public var skipReason: String? {
        switch self {
        case .allow: return nil
        case .blockedNeverDelete: return "Protected system location — not eligible for deletion."
        case .blockedNotWhitelisted: return "This item was skipped for safety."
        }
    }

    public var isUserVisibleSkip: Bool {
        self == .blockedNotWhitelisted
    }
}

public enum StorageSafetyPolicy {
    /// System-level paths that require administrator privileges — never offered.
    public static let systemDeletionPrefixes: [String] = [
        "/System",
        "/usr",
        "/bin",
        "/sbin",
        "/Library/Caches",
        "/Library/Updates",
        "/private/var/log",
        "/var/log",
        "/private/var/db",
        "/private/var/db/DiagnosticPipeline",
        "/Library/Logs/DiagnosticReports"
    ]

    /// Daemons and system services under ~/Library/Caches that must NEVER be cleaned.
    /// Wiping them triggers identity keychain password prompts or system desync.
    public static let protectedCacheFolderNames: Set<String> = [
        "CloudKit",
        "FamilyCircle",
        "com.apple.accountsd",
        "com.apple.appleaccountd",
        "com.apple.amsaccountsd",
        "com.apple.akd",
        "com.apple.AuthenticationServicesCore.AuthenticationServicesAgent",
        "com.apple.identityservicesd",
        "com.apple.passd",
        "com.apple.ProtectedCloudStorage",
        "com.apple.Security",
        "com.apple.keychainaccess",
        "com.apple.Safari.SafeBrowsing",
        "com.apple.findmy",
        "com.apple.containermanagerd",
        "com.apple.nsurlsessiond",
        "com.apple.bird",
        "com.apple.iCloudHelper",
        "com.apple.icloudwebd",
        "com.apple.itunescloudd",
        "com.apple.iCloudNotificationAgent",
        "PassKit",
        "com.docker.docker",
        "com.docker.helper",
        "com.docker.backend"
    ]

    /// Fragile folder fragments to block across all user caches
    public static let protectedFolderFragments: [String] = [
        "account",
        "identityservice",
        "keychain",
        "cloudstorage",
        "safebrowsing",
        "appleid",
        "authkit",
        "authentication",
        "authorization",
        "passkit",
        "screentime",
        "1password",
        "agilebits",
        "bitwarden",
        "lastpass",
        "dashlane",
        "keepass",
        "authy",
        "yubico",
        "inputmethod"
    ]

    public static let protectedCacheFolderPrefixes: [String] = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.controlcenter",
        "com.apple.systempreferences",
        "com.apple.settings",
        "com.apple.systemsettings",
        "com.crowdstrike.",
        "com.sentinelone.",
        "com.sentinel-labs.",
        "com.eset.",
        "com.jamf.",
        "com.jamfsoftware.",
        "com.paloaltonetworks.",
        "com.cisco.anyconnect",
        "com.cisco.secureclient"
    ]

    public static let protectedContainerBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.apple.Home",
        "com.apple.homed",
        "com.apple.HomeKit"
    ]

    public static let protectedContainerBundleIDPrefixes: [String] = [
        "com.apple.Passwords",
        "com.apple.AuthKit",
        "com.apple.AppleAccount",
        "com.apple.Accounts",
        "com.apple.PassKit",
        "com.apple.Internet-Accounts",
        "com.apple.ScreenTime",
        "com.1password",
        "com.agilebits",
        "com.bitwarden",
        "com.lastpass",
        "com.dashlane",
        "org.keepassxc",
        "com.authy",
        "com.yubico"
    ]

    public static let protectedLogFolderNames: Set<String> = [
        "DiagnosticReportsForNewHardware"
    ]

    public static let whitelistedFolderNames: Set<String> = [
        "node_modules",
        "venv",
        ".venv",
        "target",
        "Pods",
        ".gradle",
        "DerivedData",
        "build",
        "dist",
        "out",
        ".next",
        ".nuxt",
        ".cache",
        "__pycache__",
        ".turbo",
        ".parcel-cache",
        ".dart_tool"
    ]

    public static var cachedHomePath: String {
        FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
    }

    public static func neverDeletePrefixes(home: String) -> [String] {
        [
            "\(home)/Library/Keychains",
            "\(home)/Library/Preferences",
            "\(home)/Library/Mail",
            "\(home)/System",
            "\(home)/Pictures",
            "\(home)/Music",
            "\(home)/Movies",
            "/Library",
            "/usr",
            "/bin",
            "/sbin",
            "/etc",
            "/var",
            "/private"
        ]
    }

    public static func neverDeleteExactPaths(home: String) -> [String] {
        [
            home,
            "\(home)/Library",
            "\(home)/Library/Application Support",
            "\(home)/Documents",
            "\(home)/Desktop",
            "\(home)/Downloads"
        ]
    }

    public static func whitelistedAbsolutePrefixes(home: String) -> [String] {
        [
            "\(home)/Library/Caches",
            "\(home)/Library/Developer/Xcode/DerivedData",
            "\(home)/Library/Developer/Xcode/iOS DeviceSupport",
            "\(home)/Library/Developer/Xcode/Archives",
            "\(home)/Library/Developer/Xcode/DocumentationCache",
            "\(home)/Library/Developer/CoreSimulator/Devices",
            "\(home)/Library/Developer/CoreSimulator/Caches",
            "\(home)/Library/Developer/XCTestDevices",
            "\(home)/.npm",
            "\(home)/.yarn/cache",
            "\(home)/.yarn/berry/cache",
            "\(home)/.pnpm-store",
            "\(home)/Library/pnpm/store",
            "\(home)/.gradle/caches",
            "\(home)/.gradle/wrapper/dists",
            "\(home)/.android/cache",
            "\(home)/.android/build-cache",
            "\(home)/.cocoapods/repos",
            "\(home)/.ivy2/cache",
            "\(home)/.cargo/registry",
            "\(home)/.cargo/git",
            "\(home)/.pub-cache/hosted",
            "\(home)/.pub-cache/git",
            "\(home)/.bun/install/cache",
            "\(home)/.m2/repository",
            "\(home)/.gem/specs",
            "\(home)/.bundle/cache",
            "\(home)/.composer/cache",
            "\(home)/.cache/go-build",
            "\(home)/go/pkg/mod/cache",
            "\(home)/Library/Caches/JetBrains",
            "\(home)/Library/Caches/Zed",
            "\(home)/Library/Logs",
            "\(home)/Library/Logs/DiagnosticReports",
            "\(home)/Library/Application Support/Adobe/Common/Media Cache Files",
            "\(home)/Library/Application Support/Adobe/Common/Media Cache",
            "\(home)/.ollama/models",
            "\(home)/.lmstudio/models",
            "\(home)/.cache/huggingface/hub",
            "\(home)/.cache/torch/hub"
        ]
    }

    public static func isProtectedContainerBundleID(_ bundleID: String) -> Bool {
        if protectedContainerBundleIDs.contains(bundleID) { return true }
        let lower = bundleID.lowercased()
        if protectedCacheFolderPrefixes.contains(where: { lower.hasPrefix($0) }) { return true }
        if lower.contains("inputmethod") { return true }
        return protectedContainerBundleIDPrefixes.contains { bundleID.hasPrefix($0) }
    }

    public static func isWhitelistedGemDownloadCachePath(_ path: String, home: String) -> Bool {
        let root = "\(home)/.gem/ruby/"
        guard path.hasPrefix(root) else { return false }
        let parts = path.dropFirst(root.count).split(separator: "/").map(String.init)
        return parts.count >= 2 && !parts[0].isEmpty && parts[1] == "cache"
    }

    /// Evaluates whether candidate URL is permitted to be moved to Trash.
    public static func evaluate(_ url: URL) -> DeletionSafetyDecision {
        let stdPath = url.standardizedFileURL.path
        let home = cachedHomePath

        // 1. Block system root prefixes
        for prefix in systemDeletionPrefixes {
            if stdPath == prefix || stdPath.hasPrefix(prefix + "/") {
                return .blockedNeverDelete
            }
        }

        // 2. Block protected cache folder names
        let folderName = url.lastPathComponent
        if protectedCacheFolderNames.contains(folderName) {
            return .blockedNeverDelete
        }

        // 3. Block protected prefix or fragment
        for prefix in protectedCacheFolderPrefixes {
            if folderName.lowercased().hasPrefix(prefix) {
                return .blockedNeverDelete
            }
        }
        for fragment in protectedFolderFragments {
            if folderName.lowercased().contains(fragment) {
                return .blockedNeverDelete
            }
        }

        // 4. JetBrains LocalHistory protection: never offer JetBrains root or LocalHistory
        if stdPath.contains("/Library/Caches/JetBrains") {
            let relative = stdPath.replacingOccurrences(of: "\(home)/Library/Caches/JetBrains", with: "")
            let components = relative.split(separator: "/").map(String.init)
            if components.count < 2 {
                // The JetBrains root or IDE root itself
                return .blockedNeverDelete
            }
            if components.contains("LocalHistory") {
                return .blockedNeverDelete
            }
        }

        // 5. Ruby gems protection: ~/.gem and ~/.gem/ruby/*/gems must never be deleted;
        // only specs and ~/.gem/ruby/*/cache are allowed
        if stdPath.contains("/.gem") {
            if stdPath.hasSuffix("/.gem") { return .blockedNeverDelete }
            if stdPath.contains("/.gem/ruby/") && stdPath.contains("/gems") && !stdPath.contains("/cache") {
                return .blockedNeverDelete
            }
            if stdPath.contains("/.gem/ruby/") && stdPath.contains("/bin") {
                return .blockedNeverDelete
            }
        }

        // 6. Zed db protection: never offer Zed db
        if stdPath.hasSuffix("Library/Application Support/Zed/db") || stdPath.contains("Library/Application Support/Zed/db/") {
            return .blockedNeverDelete
        }

        // 7. Core user content roots & exact exclusions
        if neverDeleteExactPaths(home: home).contains(stdPath) {
            return .blockedNeverDelete
        }
        for blocked in neverDeletePrefixes(home: home) {
            if stdPath == blocked || stdPath.hasPrefix(blocked + "/") {
                return .blockedNeverDelete
            }
        }

        // 8. Whitelisted prefixes
        for prefix in whitelistedAbsolutePrefixes(home: home) {
            if stdPath == prefix || stdPath.hasPrefix(prefix + "/") {
                return .allow
            }
        }

        // Gem download cache (~/.gem/ruby/<version>/cache)
        if isWhitelistedGemDownloadCachePath(stdPath, home: home) {
            return .allow
        }

        // 9. Whitelisted project artifact / build directories within user home
        let inHome = stdPath == home || stdPath.hasPrefix(home + "/")
        if inHome {
            if whitelistedFolderNames.contains(url.lastPathComponent) {
                return .allow
            }
            // Code / Cursor workspace storage entry (e.g. 0a1b2c3d)
            if stdPath.contains("/User/workspaceStorage/") {
                return .allow
            }
        }

        return .blockedNotWhitelisted
    }

    /// Evaluates if URL is strictly safe to clean.
    public static func isSafeToClean(_ url: URL) -> Bool {
        return evaluate(url) == .allow
    }

    /// Determines the appropriate safety tier for an item, following Scopa's SafetyTierList.
    public static func safetyTier(for url: URL, category: StorageCleanupCategory) -> SafetyTier {
        // Defense-in-depth: If not allowed by deletion safety policy, never mark safeToClean
        guard evaluate(url) == .allow else {
            return .checkFirst
        }

        switch category {
        case .caches, .trash, .logs:
            return .safeToClean
        case .developer:
            let components = url.pathComponents
            let definitelySafeNames: Set<String> = [
                "DerivedData",
                "build",
                "dist",
                "out",
                "target",
                "node_modules",
                "venv",
                ".venv",
                ".next",
                ".nuxt",
                ".turbo",
                ".parcel-cache",
                "__pycache__",
                ".cache",
                "Pods",
                ".dart_tool",
                "_cacache",
                "_npx",
                "GPUCache",
                "ShaderCache",
                "Code Cache"
            ]

            // If the folder itself is a definitely safe build output or cache
            if definitelySafeNames.contains(url.lastPathComponent) {
                return .safeToClean
            }

            // Or if it is located inside Xcode DerivedData or a known build output tree
            if components.contains("DerivedData") || components.contains("build") || components.contains("dist") || components.contains("target") {
                return .safeToClean
            }

            // Items requiring explicit user discretion (e.g. Archives, simulator devices, global package repositories)
            return .checkFirst

        case .largeFiles, .downloads, .appUninstaller:
            return .checkFirst
        default:
            return .safeToClean
        }
    }
}
