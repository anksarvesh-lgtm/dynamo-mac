#!/usr/bin/env swift
import Foundation

print("=== Testing Older Version (1.9.8) Update Fetch Against Live GitHub ===")

// 1. Confirm installed version at /Applications/LiquidDynamo.app
let installedPlist = URL(fileURLWithPath: "/Applications/LiquidDynamo.app/Contents/Info.plist")
var installedVersion = "1.9.8"
if let data = try? Data(contentsOf: installedPlist),
   let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
   let ver = plist["CFBundleShortVersionString"] as? String {
    installedVersion = ver
}
print("Installed App Version at /Applications/LiquidDynamo.app: \(installedVersion)")

// 2. Fetch latest release from GitHub API (same endpoint used by GitHubUpdateChecker)
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

guard let latestVer = fetchedVersion, let tag = fetchedTag else {
    fatalError("Failed to fetch release information from GitHub")
}

print("Live GitHub Latest Release: \(tag) (Version: \(latestVer))")
print("Target Asset Download URL: \(chosenDownloadURL?.absoluteString ?? "none")")

// 3. Evaluate version comparison exactly as GitHubUpdateChecker does
func isVersion(_ v1: String, greaterThan v2: String) -> Bool {
    let clean1 = v1.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
    let clean2 = v2.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
    return clean1.compare(clean2, options: .numeric) == .orderedDescending
}

let isUpdateAvailable = isVersion(latestVer, greaterThan: installedVersion)
print("\nUpdate Evaluation:")
print(" - Current Installed Version: \(installedVersion)")
print(" - Remote GitHub Latest Version: \(latestVer)")
print(" - Is Update Available: \(isUpdateAvailable ? "YES 🟢 (Update banner & Island notification triggered)" : "NO 🔴")")

assert(isUpdateAvailable == true, "Installed version \(installedVersion) must detect available update \(latestVer)")
assert(chosenDownloadURL?.lastPathComponent == "liquiddynamo.zip", "Must select liquiddynamo.zip")

print("\n🎉 SUCCESS: Older installed version (\(installedVersion)) successfully fetched and detected v\(latestVer) update!")

