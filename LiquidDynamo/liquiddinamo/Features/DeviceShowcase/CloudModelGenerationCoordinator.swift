//
//  CloudModelGenerationCoordinator.swift
//  boringNotch
//
//  Created for Boring Notch
//

import AppKit
import Defaults
import Foundation
import SceneKit

// MARK: - Cloud Job State

public struct CloudJobState: Equatable {
    public var progress: Double
    public var statusMessage: String
    public var isGenerating: Bool
    public var error: String?

    public init(
        progress: Double = 0.0,
        statusMessage: String = "",
        isGenerating: Bool = false,
        error: String? = nil
    ) {
        self.progress = progress
        self.statusMessage = statusMessage
        self.isGenerating = isGenerating
        self.error = error
    }
}

// MARK: - Cloud Model Generation Coordinator

@MainActor
public final class CloudModelGenerationCoordinator: ObservableObject {
    public static let shared = CloudModelGenerationCoordinator()

    @Published public var activeJobs: [String: CloudJobState] = [:]

    public init() {
        checkAndResetMonthlyPeriod()
    }

    // MARK: - Monthly Quota Management

    public var monthlyCap: Int {
        Defaults[.monthlyCloudGenerationCap]
    }

    public var monthlyUsed: Int {
        checkAndResetMonthlyPeriod()
        return Defaults[.monthlyCloudGenerationsUsed]
    }

    public var remainingGenerationsThisMonth: Int {
        max(0, monthlyCap - monthlyUsed)
    }

    public func canGenerate() -> Bool {
        return monthlyUsed < monthlyCap
    }

    public func resetMonthlyUsage() {
        Defaults[.monthlyCloudGenerationsUsed] = 0
        Defaults[.monthlyCloudGenerationsPeriod] = currentPeriodIdentifier()
    }

    private func incrementUsage() {
        checkAndResetMonthlyPeriod()
        Defaults[.monthlyCloudGenerationsUsed] += 1
    }

    private func currentPeriodIdentifier() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: Date())
    }

    private func checkAndResetMonthlyPeriod() {
        let currentPeriod = currentPeriodIdentifier()
        let storedPeriod = Defaults[.monthlyCloudGenerationsPeriod]
        if storedPeriod != currentPeriod {
            Defaults[.monthlyCloudGenerationsPeriod] = currentPeriod
            Defaults[.monthlyCloudGenerationsUsed] = 0
        }
    }

    // MARK: - Job Execution

    public func jobState(for deviceKey: String) -> CloudJobState? {
        return activeJobs[deviceKey]
    }

    public func isGenerating(for deviceKey: String) -> Bool {
        return activeJobs[deviceKey]?.isGenerating ?? false
    }

    /// Starts an asynchronous 3D cloud generation job.
    /// Never blocks the main thread or the UI.
    public func startGeneration(
        for device: DeviceIdentity,
        provider: ImageTo3DProvider = MeshyImageTo3DProvider.shared,
        onComplete: (@MainActor () -> Void)? = nil
    ) {
        let key = device.stableKey

        guard !isGenerating(for: key) else { return }

        // Check monthly quota
        guard canGenerate() else {
            activeJobs[key] = CloudJobState(
                progress: 0,
                statusMessage: "Monthly generation cap reached (\(monthlyUsed)/\(monthlyCap)).",
                isGenerating: false,
                error: "Monthly limit reached. You can adjust this in Settings."
            )
            return
        }

        activeJobs[key] = CloudJobState(
            progress: 0.05,
            statusMessage: "Loading product image...",
            isGenerating: true,
            error: nil
        )

        Task { [weak self] in
            guard let self = self else { return }
            do {
                // 1. Load confirmed 1024px PNG from DeviceModelStore
                let previewURL = await DeviceModelStore.shared.previewFileURL(for: key)
                guard FileManager.default.fileExists(atPath: previewURL.path),
                      let pngData = try? Data(contentsOf: previewURL) else {
                    throw NSError(
                        domain: "CloudGeneration",
                        code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "No product image found. Please choose an image first."]
                    )
                }

                // 2. Execute cloud generation through provider
                let localUSDZURL = try await provider.generateModel(pngData: pngData) { [weak self] progress, message in
                    Task { @MainActor [weak self] in
                        self?.activeJobs[key] = CloudJobState(
                            progress: progress,
                            statusMessage: message,
                            isGenerating: true,
                            error: nil
                        )
                    }
                }

                // 3. Load USDZ data
                let modelData = try Data(contentsOf: localUSDZURL)

                // 4. Update metadata and save to Tier 1 local store
                var meta: DeviceModelMetadata
                if let existing = await DeviceModelStore.shared.getMetadata(for: key) {
                    meta = existing
                    meta.sourceTier = .aiGenerated
                    meta.provider = provider.id
                    meta.lastSeenAt = Date()
                    meta.fileSizeBytes = Int64(modelData.count)
                } else {
                    meta = DeviceModelMetadata(
                        deviceKey: key,
                        deviceName: device.displayName,
                        kind: device.kind.rawValue,
                        sourceTier: .aiGenerated,
                        provider: provider.id,
                        sourceURL: nil,
                        createdAt: Date(),
                        lastSeenAt: Date(),
                        fileSizeBytes: Int64(modelData.count)
                    )
                }

                _ = try await DeviceModelStore.shared.saveModel(
                    deviceKey: key,
                    modelData: modelData,
                    previewData: pngData,
                    metadata: meta
                )

                // 5. Increment monthly usage
                self.incrementUsage()

                // 6. Clear memory cache so SceneKit renders new USDZ immediately
                DeviceModelResolver.shared.clearMemoryCache()

                // 7. Mark job as succeeded
                self.activeJobs[key] = CloudJobState(
                    progress: 1.0,
                    statusMessage: "Model generated successfully!",
                    isGenerating: false,
                    error: nil
                )

                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                onComplete?()

                // Clean up job state after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                    if self?.activeJobs[key]?.isGenerating == false {
                        self?.activeJobs.removeValue(forKey: key)
                    }
                }
            } catch {
                self.activeJobs[key] = CloudJobState(
                    progress: 0.0,
                    statusMessage: "Generation failed",
                    isGenerating: false,
                    error: error.localizedDescription
                )
            }
        }
    }
}
