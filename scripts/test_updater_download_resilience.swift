import Foundation

// Test script: test_updater_download_resilience.swift
// Simulates the multi-candidate URL fallback logic implemented in GitHubUpdateChecker.swift

let repoOwner = "anksarvesh-lgtm"
let repoName = "dynamo-mac"
let fallbackRepoName = "dynamomac"
let permanentZipURL = URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/download/app/liquiddynamo.zip")!
let permanentDMGURL = URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/download/app/LiquidDynamo.dmg")!

func sanitizeDownloadURL(_ url: URL) -> URL {
    var str = url.absoluteString
    if str.contains("banksarvesh-lgtm/dynamomac") {
        str = str.replacingOccurrences(of: "banksarvesh-lgtm/dynamomac", with: "\(repoOwner)/\(repoName)")
    }
    return URL(string: str) ?? url
}

func buildDownloadCandidates(targetURL: URL?, version: String) -> [URL] {
    var candidates: [URL] = []
    var seen = Set<String>()

    func add(_ url: URL?) {
        guard let url = url else { return }
        let sanitized = sanitizeDownloadURL(url)
        let key = sanitized.absoluteString.lowercased()
        if !seen.contains(key) {
            seen.insert(key)
            candidates.append(sanitized)
        }
    }

    add(targetURL)
    let cleanVersion = version.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
    if !cleanVersion.isEmpty {
        add(URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/download/v\(cleanVersion)/liquiddynamo.zip"))
        add(URL(string: "https://github.com/\(repoOwner)/\(fallbackRepoName)/releases/download/v\(cleanVersion)/liquiddynamo.zip"))
    }
    add(permanentZipURL)
    add(URL(string: "https://github.com/\(repoOwner)/\(fallbackRepoName)/releases/download/app/liquiddynamo.zip"))

    if !cleanVersion.isEmpty {
        add(URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/download/v\(cleanVersion)/LiquidDynamo-\(cleanVersion).dmg"))
        add(URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/download/v\(cleanVersion)/LiquidDynamo.dmg"))
        add(URL(string: "https://github.com/\(repoOwner)/\(fallbackRepoName)/releases/download/v\(cleanVersion)/LiquidDynamo-\(cleanVersion).dmg"))
        add(URL(string: "https://github.com/\(repoOwner)/\(fallbackRepoName)/releases/download/v\(cleanVersion)/LiquidDynamo.dmg"))
    }
    add(permanentDMGURL)
    add(URL(string: "https://github.com/\(repoOwner)/\(fallbackRepoName)/releases/download/app/LiquidDynamo.dmg"))

    return candidates
}

let group = DispatchGroup()
group.enter()

Task {
    print("Testing updater download fallback resilience...")

    // 1. Deliberately start with an intentional 404 URL as the primary target to test fallback recovery
    let intentional404URL = URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/download/v9.9.9-nonexistent/liquiddynamo.zip")!
    let candidates = buildDownloadCandidates(targetURL: intentional404URL, version: "1.9.9")

    print("Generated \(candidates.count) candidates:")
    for (i, c) in candidates.enumerated() {
        print("  [\(i+1)] \(c.absoluteString)")
    }

    var succeeded = false
    var successfulCandidate: URL? = nil
    var bytesReceived: Int = 0

    for (index, candidateURL) in candidates.enumerated() {
        print("\nAttempting candidate #\(index + 1): \(candidateURL.absoluteString)")
        do {
            var request = URLRequest(url: candidateURL)
            request.timeoutInterval = 30
            request.setValue("LiquidDynamo-AutoUpdater", forHTTPHeaderField: "User-Agent")

            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                print("  -> Invalid response, continuing...")
                continue
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                print("  -> HTTP \(httpResponse.statusCode) received (expected for invalid candidate). Falling back smoothly to next candidate...")
                continue
            }

            print("  -> HTTP \(httpResponse.statusCode) OK! Reading initial byte stream...")
            var count = 0
            for try await _ in asyncBytes {
                count += 1
                if count >= 32768 { // Sample 32 KB to confirm healthy streaming
                    break
                }
            }

            print("  -> Successfully received \(count) bytes from live server!")
            succeeded = true
            successfulCandidate = candidateURL
            bytesReceived = count
            break
        } catch {
            print("  -> Error: \(error.localizedDescription). Falling back...")
        }
    }

    if succeeded, let match = successfulCandidate {
        print("\n✅ RESILIENCE TEST PASSED!")
        print("Successfully recovered from 404 and streamed update archive from: \(match.absoluteString) (bytes read: \(bytesReceived))")
    } else {
        print("\n❌ RESILIENCE TEST FAILED! None of the candidates could be retrieved.")
        exit(1)
    }

    group.leave()
}

group.wait()
