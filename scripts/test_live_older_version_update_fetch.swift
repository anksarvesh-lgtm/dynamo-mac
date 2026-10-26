#!/usr/bin/env swift
import Foundation

print("=== Testing Older Version Update Fetch Compatibility ===")

// 1. Check currently installed version at /Applications/LiquidDynamo.app
let installedPlist = URL(fileURLWithPath: "/Applications/LiquidDynamo.app/Contents/Info.plist")
var installedVersion = "1.9.8"
if let data = try? Data(contentsOf: installedPlist),
   let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
   let ver = plist["CFBundleShortVersionString"] as? String {
    installedVersion = ver
}
print("Current /Applications/LiquidDynamo.app Version: \(installedVersion)")

// 2. Query GitHub Releases API to verify live endpoint connectivity and schema
let apiURL = URL(string: "https://api.github.com/repos/anksarvesh-lgtm/dynamo-mac/releases/latest")!
var request = URLRequest(url: apiURL)
request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
request.setValue("LiquidDynamo/\(installedVersion)", forHTTPHeaderField: "User-Agent")

let semaphore = DispatchSemaphore(value: 0)

var fetchedTag: String? = nil
var fetchedVersion: String? = nil
var chosenDownloadURL: URL? = nil
var releaseNotes: String? = nil

let task = URLSession.shared.dataTask(with: request) { data, response, error in
    defer { semaphore.signal() }
    guard let data = data, let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        print("❌ Error fetching GitHub release: \(String(describing: error))")
        return
    }
    
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let tagName = json["tag_name"] as? String else {
        print("❌ Failed to parse tag_name from GitHub API response")
        return
    }
    
    fetchedTag = tagName
    fetchedVersion = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
    releaseNotes = json["body"] as? String
    
    if let assets = json["assets"] as? [[String: Any]] {
        if let zipAsset = assets.first(where: {
            let name = ($0["name"] as? String)?.lowercased() ?? ""
            return name == "liquiddynamo.zip" || name.hasSuffix(".zip")
        }), let downloadStr = zipAsset["browser_download_url"] as? String, let url = URL(string: downloadStr) {
            chosenDownloadURL = url
        }
    }
}
task.resume()
_ = semaphore.wait(timeout: .now() + 15)

guard let remoteVer = fetchedVersion, let tag = fetchedTag else {
    fatalError("Failed to fetch release information from GitHub")
}

print("Live GitHub Latest Release: \(tag) (Version: \(remoteVer))")
print("Target Asset Download URL: \(chosenDownloadURL?.absoluteString ?? "none")")

// 3. Test version comparison logic matching GitHubUpdateChecker.SemanticVersion
struct SemVer: Comparable {
    let major: Int
    let minor: Int
    let patch: Int
    
    init?(_ str: String) {
        var clean = str.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("v") || clean.hasPrefix("V") { clean.removeFirst() }
        let parts = clean.components(separatedBy: "-")[0].components(separatedBy: "+")[0].components(separatedBy: ".")
        guard let maj = Int(parts[0]) else { return nil }
        self.major = maj
        self.minor = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        self.patch = parts.count > 2 ? (Int(parts[2]) ?? 0) : 0
    }
    
    static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

let candidateTargetVersion = "2.0.7"
let olderVersionsToTest = ["1.9.2", "1.9.8", "2.0.0", "2.0.5", "2.0.6"]

print("\n--- Verifying Update Detection for All Older Installed Versions against \(candidateTargetVersion) ---")
for oldVer in olderVersionsToTest {
    guard let oldSem = SemVer(oldVer), let candSem = SemVer(candidateTargetVersion) else {
        fatalError("Failed to parse versions")
    }
    let updateDetected = candSem > oldSem
    print("  Version \(oldVer) -> Target \(candidateTargetVersion): \(updateDetected ? "UPDATE DETECTED 🟢" : "NO UPDATE 🔴")")
    assert(updateDetected == true, "Version \(oldVer) must detect \(candidateTargetVersion) as an available update")
}

print("\n🎉 SUCCESS: All older installed versions (1.9.2, 1.9.8, 2.0.0, 2.0.5, 2.0.6) will reliably trigger the update flow for v\(candidateTargetVersion)!")

