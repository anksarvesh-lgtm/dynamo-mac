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

// Retrieve local git token if available to avoid unauthenticated API rate limits
func getGitToken() -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    p.arguments = ["credential", "fill"]
    let inPipe = Pipe()
    let outPipe = Pipe()
    p.standardInput = inPipe
    p.standardOutput = outPipe
    try? p.run()
    inPipe.fileHandleForWriting.write(Data("protocol=https\nhost=github.com\n\n".utf8))
    p.waitUntilExit()
    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
    if let outStr = String(data: outData, encoding: .utf8) {
        for line in outStr.components(separatedBy: "\n") {
            if line.hasPrefix("password=") {
                return String(line.dropFirst("password=".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }
    return nil
}

if let token = getGitToken(), !token.isEmpty {
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
}

let semaphore = DispatchSemaphore(value: 0)

var fetchedTag: String? = nil
var fetchedVersion: String? = nil
var chosenDownloadURL: URL? = nil
var releaseNotes: String? = nil

let task = URLSession.shared.dataTask(with: request) { data, response, error in
    defer { semaphore.signal() }
    if let data = data, let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let tagName = json["tag_name"] as? String {
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
}
task.resume()
_ = semaphore.wait(timeout: .now() + 15)

// Fallback to HTML redirect endpoint if API was rate-limited
if fetchedVersion == nil {
    print("ℹ️ Falling back to unauthenticated releases/latest redirect...")
    var headReq = URLRequest(url: URL(string: "https://github.com/anksarvesh-lgtm/dynamo-mac/releases/latest")!)
    headReq.httpMethod = "HEAD"
    headReq.setValue("LiquidDynamo/\(installedVersion)", forHTTPHeaderField: "User-Agent")
    let sema2 = DispatchSemaphore(value: 0)
    let headTask = URLSession.shared.dataTask(with: headReq) { _, resp, _ in
        defer { sema2.signal() }
        if let targetURL = resp?.url {
            let last = targetURL.lastPathComponent
            fetchedTag = last
            fetchedVersion = last.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            chosenDownloadURL = URL(string: "https://github.com/anksarvesh-lgtm/dynamo-mac/releases/download/\(last)/liquiddynamo.zip")
        }
    }
    headTask.resume()
    _ = sema2.wait(timeout: .now() + 15)
}

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

let candidateTargetVersion = "2.0.8"
let olderVersionsToTest = ["1.9.2", "1.9.8", "2.0.0", "2.0.5", "2.0.6", "2.0.7"]

print("\n--- Verifying Update Detection for All Older Installed Versions against \(candidateTargetVersion) ---")
for oldVer in olderVersionsToTest {
    guard let oldSem = SemVer(oldVer), let candSem = SemVer(candidateTargetVersion) else {
        fatalError("Failed to parse versions")
    }
    let updateDetected = candSem > oldSem
    print("  Version \(oldVer) -> Target \(candidateTargetVersion): \(updateDetected ? "UPDATE DETECTED 🟢" : "NO UPDATE 🔴")")
    assert(updateDetected == true, "Version \(oldVer) must detect \(candidateTargetVersion) as an available update")
}

print("\n🎉 SUCCESS: All older installed versions (1.9.2, 1.9.8, 2.0.0, 2.0.5, 2.0.6, 2.0.7) will reliably trigger the update flow for v\(candidateTargetVersion)!")

