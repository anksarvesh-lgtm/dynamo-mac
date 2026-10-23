//
//  ImageTo3DProvider.swift
//  boringNotch
//
//  Created for Boring Notch
//

import Foundation

// MARK: - Image to 3D Error

public enum ImageTo3DError: LocalizedError {
    case missingApiKey(provider: String)
    case monthlyQuotaExceeded(used: Int, cap: Int)
    case unauthorized(String)
    case paymentRequired(String)
    case rateLimited(String)
    case taskFailed(String)
    case timeout(Int)
    case invalidResponse(String)
    case invalidModelData
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .missingApiKey(let provider):
            return "\(provider) API Key is missing. Please add it in Settings."
        case .monthlyQuotaExceeded(let used, let cap):
            return "Monthly generation cap reached (\(used)/\(cap)). You can adjust this limit in Settings."
        case .unauthorized(let msg):
            return "Authentication failed (401): \(msg)"
        case .paymentRequired(let msg):
            return "Insufficient credits (402): \(msg)"
        case .rateLimited(let msg):
            return "Rate limit exceeded (429): \(msg)"
        case .taskFailed(let msg):
            return "3D Generation failed: \(msg)"
        case .timeout(let seconds):
            return "Generation timed out after \(seconds) seconds. Please try again."
        case .invalidResponse(let msg):
            return "Invalid server response: \(msg)"
        case .invalidModelData:
            return "Downloaded 3D model could not be verified in SceneKit."
        case .networkError(let msg):
            return "Network connection error: \(msg)"
        }
    }
}

// MARK: - Image to 3D Provider Protocol

/// Protocol for AI Image-to-3D cloud generation providers.
/// Enables seamless addition of future providers (e.g. Tripo3D, CSM, Rodin).
public protocol ImageTo3DProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var estimatedCreditCost: Int { get }

    /// Executes the complete 3D generation flow from a 1024px transparent PNG.
    /// - Parameters:
    ///   - pngData: 1024x1024 transparent PNG data.
    ///   - onProgress: Closure called with progress (0.0 ... 1.0) and status description.
    /// - Returns: Local URL to the downloaded and verified USDZ file.
    func generateModel(
        pngData: Data,
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> URL
}
