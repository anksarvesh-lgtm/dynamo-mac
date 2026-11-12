//
//  MediaChecker.swift
//  LiquidDynamo
//
//  LiquidDynamo Core Team
//

import Foundation

final class MediaChecker: Sendable {

    enum MediaCheckerError: Error {
        case missingResources
        case processExecutionFailed
        case timeout
    }

    func checkDeprecationStatus() async throws -> Bool {
        if MediaBackendEligibility.isSandboxedRuntime {
            return true
        }

        let hasAdapterResources = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl") != nil
            && Bundle.main.url(forResource: "MediaRemoteAdapterTestClient", withExtension: nil) != nil
            && Bundle.main.privateFrameworksPath?.appending("/MediaRemoteAdapter.framework") != nil

        guard MediaBackendEligibility.adapterEligible(
            isSandboxed: MediaBackendEligibility.isSandboxedRuntime,
            hasAdapterResources: hasAdapterResources
        ) else {
            let osVersion = MediaBackendEligibility.currentOSVersion
            let directEligible = MediaBackendEligibility.directMediaRemoteEligible(
                osMajor: osVersion.major,
                osMinor: osVersion.minor,
                isSandboxed: MediaBackendEligibility.isSandboxedRuntime
            )
            return !directEligible
        }

        return try await Task.detached(priority: .userInitiated) {
            guard let scriptURL = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
                  let nowPlayingTestClientPath = Bundle.main.url(forResource: "MediaRemoteAdapterTestClient", withExtension: nil)?.path,
                  let frameworkPath = Bundle.main.privateFrameworksPath?.appending("/MediaRemoteAdapter.framework")
            else {
                return true
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            process.arguments = [scriptURL.path, frameworkPath, nowPlayingTestClientPath, "test"]

            do {
                try process.run()
            } catch {
                return true
            }

            // Timeout after 10 seconds
            let didExit: Bool = try await withThrowingTaskGroup(of: Bool.self) { group in
                group.addTask {
                    process.waitUntilExit()
                    return true
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(10))
                    if process.isRunning {
                        process.terminate()
                    }
                    return false // Timed out
                }
                for try await exited in group {
                    if exited {
                        group.cancelAll()
                        return true
                    }
                }
                return false
            }

            if !didExit {
                return true
            }

            let isDeprecated = process.terminationStatus == 1
            return isDeprecated
        }.value
    }
}
