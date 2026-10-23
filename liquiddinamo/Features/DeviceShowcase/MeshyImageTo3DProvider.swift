//
//  MeshyImageTo3DProvider.swift
//  boringNotch
//
//  Created for Boring Notch
//

import AppKit
import Foundation
import SceneKit

// MARK: - Decodable Meshy Responses

private struct MeshyCreateTaskResponse: Decodable {
    let result: String
}

private struct MeshyTaskResponse: Decodable {
    let id: String
    let status: String
    let progress: Int?
    let modelUrls: [String: String]?
    let taskError: MeshyTaskError?
    let consumedCredits: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case progress
        case modelUrls = "model_urls"
        case taskError = "task_error"
        case consumedCredits = "consumed_credits"
    }
}

private struct MeshyTaskError: Decodable {
    let message: String?
}

// MARK: - Meshy Image to 3D Provider

public final class MeshyImageTo3DProvider: ImageTo3DProvider, @unchecked Sendable {
    public static let shared = MeshyImageTo3DProvider()

    public let id: String = "meshy"
    public let displayName: String = "Meshy AI (Meshy 7.1)"
    public let estimatedCreditCost: Int = 20

    private let session: URLSession
    private let baseURL = URL(string: "https://api.meshy.ai/openapi/v1/image-to-3d")!

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func generateModel(
        pngData: Data,
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> URL {
        // 1. Retrieve API key from secure Keychain (never printed or logged)
        guard let apiKey = KeychainService.shared.getMeshyKey(), !apiKey.isEmpty else {
            throw ImageTo3DError.missingApiKey(provider: "Meshy")
        }

        onProgress(0.05, "Preparing high-res image payload...")

        // 2. Encode confirmed 1024px PNG as Base64 Data URI
        let base64String = pngData.base64EncodedString()
        let dataURI = "data:image/png;base64,\(base64String)"

        // 3. Create task payload: optimized polycount & 2k textures for notch-sized 3D
        let payload: [String: Any] = [
            "image_url": dataURI,
            "ai_model": "latest",
            "should_texture": true,
            "texture_resolution": "2k",
            "should_remesh": true,
            "target_polycount": 8000,
            "target_formats": ["usdz"]
        ]

        let httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody
        request.timeoutInterval = 30.0

        onProgress(0.10, "Uploading image to Meshy cloud...")

        let (createData, createResponse): (Data, URLResponse)
        do {
            (createData, createResponse) = try await session.data(for: request)
        } catch {
            throw ImageTo3DError.networkError(error.localizedDescription)
        }

        guard let httpResponse = createResponse as? HTTPURLResponse else {
            throw ImageTo3DError.invalidResponse("Invalid response received from server.")
        }

        // Handle HTTP Error Codes
        try handleHTTPError(statusCode: httpResponse.statusCode, responseData: createData)

        let createDecoded: MeshyCreateTaskResponse
        do {
            createDecoded = try JSONDecoder().decode(MeshyCreateTaskResponse.self, from: createData)
        } catch {
            throw ImageTo3DError.invalidResponse("Failed to parse task creation response.")
        }

        let taskID = createDecoded.result
        onProgress(0.15, "Task queued in Meshy cloud (ID: \(taskID.prefix(8))...)")

        // 4. Poll task status with backoff (max 5 minutes)
        let modelURL = try await pollTaskUntilComplete(
            taskID: taskID,
            apiKey: apiKey,
            onProgress: onProgress
        )

        // 5. Download the generated USDZ file
        onProgress(0.92, "Downloading USDZ 3D model...")
        let localURL = try await downloadUSDZ(from: modelURL, taskID: taskID)

        // 6. Verify that SceneKit can load and parse the USDZ scene and normalize it
        onProgress(0.97, "Verifying and normalizing 3D mesh geometry in SceneKit...")
        do {
            let scene = try SCNScene(url: localURL, options: nil)
            guard scene.rootNode.childNodes.count > 0 || scene.rootNode.geometry != nil else {
                throw ImageTo3DError.invalidModelData
            }

            // Normalize node bounding box to unit scale for notch icon display
            SceneKitDeviceRenderer.normalize(node: scene.rootNode, targetSize: 1.0)

            // Re-export normalized scene to USDZ if supported; fallback to verified localURL
            let normalizedURL = localURL.deletingLastPathComponent().appendingPathComponent("\(taskID)_normalized.usdz")
            if scene.write(to: normalizedURL, options: nil, delegate: nil, progressHandler: nil) {
                onProgress(1.0, "3D generation complete!")
                return normalizedURL
            }
        } catch {
            throw ImageTo3DError.invalidModelData
        }

        onProgress(1.0, "3D generation complete!")
        return localURL
    }

    // MARK: - Polling with Backoff

    private func pollTaskUntilComplete(
        taskID: String,
        apiKey: String,
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> URL {
        let taskURL = baseURL.appendingPathComponent(taskID)
        let startTime = Date()
        let timeoutSeconds: TimeInterval = 300 // 5 minutes hard limit

        var currentDelay: TimeInterval = 2.5
        let maxDelay: TimeInterval = 5.0
        let backoffMultiplier: Double = 1.25

        while Date().timeIntervalSince(startTime) < timeoutSeconds {
            try Task.checkCancellation()

            // Wait with backoff delay
            try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
            currentDelay = min(currentDelay * backoffMultiplier, maxDelay)

            var pollRequest = URLRequest(url: taskURL)
            pollRequest.httpMethod = "GET"
            pollRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            pollRequest.timeoutInterval = 15.0

            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session.data(for: pollRequest)
            } catch {
                // Temporary network blip: retry next cycle
                continue
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                continue
            }

            try handleHTTPError(statusCode: httpResponse.statusCode, responseData: data)

            guard let task = try? JSONDecoder().decode(MeshyTaskResponse.self, from: data) else {
                continue
            }

            let status = task.status.uppercased()
            let rawProgress = task.progress ?? 0
            // Map Meshy 0-100 progress into 0.15 - 0.90 range
            let mappedProgress = 0.15 + (Double(rawProgress) / 100.0) * 0.75

            switch status {
            case "PENDING":
                onProgress(mappedProgress, "Job waiting in queue...")
            case "IN_PROGRESS":
                onProgress(mappedProgress, "Generating 3D model (\(rawProgress)%)...")
            case "SUCCEEDED":
                guard let usdzString = task.modelUrls?["usdz"],
                      let usdzURL = URL(string: usdzString) else {
                    throw ImageTo3DError.invalidResponse("Meshy task succeeded but returned no USDZ output URL.")
                }
                return usdzURL
            case "FAILED":
                let message = task.taskError?.message ?? "Generation failed in Meshy cloud."
                throw ImageTo3DError.taskFailed(message)
            case "EXPIRED":
                throw ImageTo3DError.taskFailed("Meshy generation task expired.")
            default:
                onProgress(mappedProgress, "Processing 3D geometry...")
            }
        }

        throw ImageTo3DError.timeout(Int(timeoutSeconds))
    }

    // MARK: - Download USDZ

    private func downloadUSDZ(from remoteURL: URL, taskID: String) async throws -> URL {
        var request = URLRequest(url: remoteURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 60.0

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw ImageTo3DError.networkError("Failed to download generated USDZ file from cloud storage.")
        }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("MeshyDownloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let localURL = tempDir.appendingPathComponent("\(taskID).usdz")
        try data.write(to: localURL, options: .atomic)
        return localURL
    }

    // MARK: - Error Handling

    private func handleHTTPError(statusCode: Int, responseData: Data) throws {
        if statusCode == 200 || statusCode == 201 || statusCode == 202 {
            return
        }

        var message = "HTTP \(statusCode)"
        if let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
            if let msg = json["message"] as? String {
                message = msg
            } else if let errorObj = json["error"] as? [String: Any], let msg = errorObj["message"] as? String {
                message = msg
            }
        }

        switch statusCode {
        case 401:
            throw ImageTo3DError.unauthorized("Authentication failed. Please check your Meshy API Key.")
        case 402:
            throw ImageTo3DError.paymentRequired("Insufficient credits in your Meshy account to perform this task.")
        case 429:
            throw ImageTo3DError.rateLimited("Too many requests sent to Meshy. Please wait before trying again.")
        default:
            throw ImageTo3DError.invalidResponse(message)
        }
    }
}
