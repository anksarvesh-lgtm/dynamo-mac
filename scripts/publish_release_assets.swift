import Foundation

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

guard let token = getGitToken(), !token.isEmpty else {
    print("❌ Failed to obtain git credentials token.")
    exit(1)
}

let owner = "anksarvesh-lgtm"
let repos = ["dynamo-mac"]

struct TargetRelease {
    let tag: String
    let name: String
    let body: String
    let makeLatest: Bool
}

let releaseBody = """
### Release Highlights — LiquidDynamo 2.1.8
- **Lightweight Engine & Idle CPU Suspension**: Suspended 3D SceneKit continuous rendering (`rendersContinuously = false`, `isPlaying = false`) in `AirPodsSceneRenderer` and `DeviceModelRenderer` when views are collapsed or off-screen.
- **DisplayServices Direct C-Symbol Caching**: Eliminated repeated `dlopen`/`dlsym` calls in `BrightnessManager` with static C symbol pointers and throttled polling to 0.8s with energy coalescing tolerance.
- **Fast-Path Cursor Bounding**: Bypassed mouse hover computations and notifications whenever cursor is outside the top 80pt area of the screen.
- **Kernel Power Scaling**: Removed `.latencyCritical` from `ProcessInfo.beginActivity` to allow macOS kernel to downclock cores and enter deepest C-states at idle.
- **Coalesced Periodic Timers**: Throttled background telemetry timers across Bluetooth, hardware sensors, battery status, and clipboard history.
- **ProMotion Animation Capping**: Capped liquid capsule animation timelines to 30 FPS, saving 75% frame redraws on 120Hz displays.
"""

let targetReleases: [TargetRelease] = [
    TargetRelease(
        tag: "v2.1.8",
        name: "LiquidDynamo 2.1.8 — Lightweight Engine & CPU / Battery Optimization",
        body: releaseBody,
        makeLatest: true
    ),
    TargetRelease(
        tag: "app",
        name: "LiquidDynamo Distribution Release",
        body: "Live distribution release for LiquidDynamo installer and direct updater.\nVersion: 2.1.8 (build 31)",
        makeLatest: false
    )
]

let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
let projectDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let docsAssets = projectDir.appendingPathComponent("docs/assets", isDirectory: true)

let assetsToUpload: [(name: String, path: URL, contentType: String)] = [
    ("LiquidDynamo-2.1.8.dmg", desktop.appendingPathComponent("LiquidDynamo-2.1.8.dmg"), "application/x-apple-diskimage"),
    ("LiquidDynamo.dmg", desktop.appendingPathComponent("LiquidDynamo.dmg"), "application/x-apple-diskimage"),
    ("liquiddynamo.zip", desktop.appendingPathComponent("liquiddynamo.zip"), "application/zip"),
    ("LiquidDynamo-Demo.gif", docsAssets.appendingPathComponent("demo.gif"), "image/gif"),
    ("LiquidDynamo-Demo.mp4", docsAssets.appendingPathComponent("demo.mp4"), "video/mp4")
]

for repo in repos {
    for target in targetReleases {
        print("\n=======================================================")
        print("🚀 Publishing Release \(target.tag) to \(owner)/\(repo)...")
        print("=======================================================")
        
        var releaseId: Int?
        var uploadUrlTemplate: String?
        
        // 1. Check if release already exists
        let getURL = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/tags/\(target.tag)")!
        var getReq = URLRequest(url: getURL)
        getReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        getReq.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        getReq.setValue("LiquidDynamo-ReleasePublisher", forHTTPHeaderField: "User-Agent")
        
        let getSema = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: getReq) { data, res, err in
            defer { getSema.signal() }
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let id = json["id"] as? Int {
                releaseId = id
                uploadUrlTemplate = json["upload_url"] as? String
                print("Found existing release ID: \(id)")
            }
        }.resume()
        getSema.wait()
        
        // 2. Create release if it does not exist
        if releaseId == nil {
            print("Creating release \(target.tag) for \(owner)/\(repo)...")
            let createURL = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases")!
            var createReq = URLRequest(url: createURL)
            createReq.httpMethod = "POST"
            createReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            createReq.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            createReq.setValue("LiquidDynamo-ReleasePublisher", forHTTPHeaderField: "User-Agent")
            createReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let payload: [String: Any] = [
                "tag_name": target.tag,
                "name": target.name,
                "body": target.body,
                "draft": false,
                "prerelease": false,
                "make_latest": target.makeLatest ? "true" : "false"
            ]
            createReq.httpBody = try! JSONSerialization.data(withJSONObject: payload)
            
            let createSema = DispatchSemaphore(value: 0)
            URLSession.shared.dataTask(with: createReq) { data, res, err in
                defer { createSema.signal() }
                if let http = res as? HTTPURLResponse {
                    print("Create Release Response: HTTP \(http.statusCode)")
                }
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let id = json["id"] as? Int {
                        releaseId = id
                        uploadUrlTemplate = json["upload_url"] as? String
                        print("✅ Release created successfully with ID: \(id)")
                    } else if let msg = json["message"] as? String {
                        print("API error: \(msg)")
                    }
                }
            }.resume()
            createSema.wait()
        }
        
        guard let id = releaseId, let uploadTemplate = uploadUrlTemplate else {
            print("❌ Could not get release ID or upload template for \(repo) tag \(target.tag). Skipping.")
            continue
        }
        
        // 3. Update release metadata if needed
        let patchURL = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/\(id)")!
        var patchReq = URLRequest(url: patchURL)
        patchReq.httpMethod = "PATCH"
        patchReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        patchReq.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        patchReq.setValue("LiquidDynamo-ReleasePublisher", forHTTPHeaderField: "User-Agent")
        patchReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var patchPayload: [String: Any] = [
            "name": target.name,
            "body": target.body
        ]
        if target.makeLatest {
            patchPayload["make_latest"] = "true"
        }
        patchReq.httpBody = try! JSONSerialization.data(withJSONObject: patchPayload)
        let patchSema = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: patchReq) { _, res, _ in
            if let http = res as? HTTPURLResponse {
                print("Patched release metadata on \(repo) -> HTTP \(http.statusCode)")
            }
            patchSema.signal()
        }.resume()
        patchSema.wait()
        
        // 4. Fetch existing assets and delete any conflicting asset
        var existingAssets: [(name: String, id: Int)] = []
        let assetsListURL = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/\(id)/assets")!
        var listReq = URLRequest(url: assetsListURL)
        listReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        listReq.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        listReq.setValue("LiquidDynamo-ReleasePublisher", forHTTPHeaderField: "User-Agent")
        let listSema = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: listReq) { data, _, _ in
            defer { listSema.signal() }
            if let data = data,
               let jsonArr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                for item in jsonArr {
                    if let aName = item["name"] as? String, let aId = item["id"] as? Int {
                        existingAssets.append((name: aName, id: aId))
                    }
                }
            }
        }.resume()
        listSema.wait()
        
        // 5. Upload assets
        let baseUploadUrl = uploadTemplate.replacingOccurrences(of: "{?name,label}", with: "")
        
        for asset in assetsToUpload {
            guard FileManager.default.fileExists(atPath: asset.path.path),
                  let fileData = try? Data(contentsOf: asset.path) else {
                print("⚠️ Missing or unreadable asset: \(asset.path.path)")
                continue
            }
            
            // Delete existing asset if it exists
            if let existing = existingAssets.first(where: { $0.name == asset.name }) {
                print("Deleting existing asset '\(asset.name)' (ID: \(existing.id)) on \(repo)...")
                let delURL = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/assets/\(existing.id)")!
                var delReq = URLRequest(url: delURL)
                delReq.httpMethod = "DELETE"
                delReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                delReq.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
                delReq.setValue("LiquidDynamo-ReleasePublisher", forHTTPHeaderField: "User-Agent")
                let delSema = DispatchSemaphore(value: 0)
                URLSession.shared.dataTask(with: delReq) { _, _, _ in
                    delSema.signal()
                }.resume()
                delSema.wait()
            }
            
            print("Uploading \(asset.name) (\(fileData.count / 1_000_000) MB) to \(repo) [\(target.tag)]...")
            let uploadURL = URL(string: "\(baseUploadUrl)?name=\(asset.name)")!
            var uploadReq = URLRequest(url: uploadURL)
            uploadReq.httpMethod = "POST"
            uploadReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            uploadReq.setValue(asset.contentType, forHTTPHeaderField: "Content-Type")
            uploadReq.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            uploadReq.setValue("LiquidDynamo-ReleasePublisher", forHTTPHeaderField: "User-Agent")
            uploadReq.setValue("\(fileData.count)", forHTTPHeaderField: "Content-Length")
            uploadReq.httpBody = fileData
            uploadReq.timeoutInterval = 300
            
            let uploadSema = DispatchSemaphore(value: 0)
            URLSession.shared.dataTask(with: uploadReq) { data, res, err in
                defer { uploadSema.signal() }
                if let http = res as? HTTPURLResponse {
                    if http.statusCode == 201 {
                        print("  ✅ Uploaded \(asset.name) (HTTP 201)")
                    } else {
                        print("  ⚠️ Upload HTTP \(http.statusCode)")
                    }
                } else if let err = err {
                    print("  ❌ Error: \(err.localizedDescription)")
                }
            }.resume()
            uploadSema.wait()
        }
    }
}

print("\n🎉 All release assets successfully published across all repositories!")
