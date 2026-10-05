//
//  NetworkThroughputService.swift
//  boringNotch
//
//  Created for Boring Notch
//

import Combine
import Darwin
import Foundation
import SwiftUI

// MARK: - Models

/// A single timestamped throughput measurement.
public struct ThroughputSample: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let downloadBytesPerSecond: Double
    public let uploadBytesPerSecond: Double

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        downloadBytesPerSecond: Double,
        uploadBytesPerSecond: Double
    ) {
        self.id = id
        self.timestamp = timestamp
        self.downloadBytesPerSecond = max(0, downloadBytesPerSecond)
        self.uploadBytesPerSecond = max(0, uploadBytesPerSecond)
    }
}

// MARK: - Network Throughput Service

/// Service measuring real-time network throughput (upload & download rates) once per second using `getifaddrs`.
///
/// Features:
/// - Reads low-level hardware link byte counters (`ifi_ibytes` / `ifi_obytes`) directly from BSD Darwin `if_data`.
/// - Targets the primary active physical interface identified by `NWPathMonitor` (e.g. `en0`), completely ignoring
///   loopback (`lo0`), VPN tunnels (`utun*`), tap, bridge, and Apple direct links (`awdl*`) so VPN traffic is never counted twice.
/// - Retains the last 60 1-second samples for mini sparkline or graph rendering.
/// - Strictly operates only when the Network tab or live speed indicator is visible.
/// - `start()` and `stop()` fully allocate and cancel `DispatchSourceTimer` to guarantee ~0% CPU when hidden.
/// - Zero network requests: strictly passive local interface counter reads.
@MainActor
public final class NetworkThroughputService: ObservableObject {
    public static let shared = NetworkThroughputService()

    // MARK: - Published Properties

    @Published public private(set) var downloadBytesPerSecond: Double = 0.0
    @Published public private(set) var uploadBytesPerSecond: Double = 0.0
    @Published public private(set) var currentInterfaceName: String = "en0"
    @Published public private(set) var history: [ThroughputSample] = []
    @Published public private(set) var isRunning: Bool = false

    // MARK: - Private State

    private var timer: DispatchSourceTimer?
    private var previousSampleTime: Date?
    private var previousInBytes: UInt32?
    private var previousOutBytes: UInt32?
    private let queue = DispatchQueue(label: "com.agrigence.liquiddynamo.throughput", qos: .utility)
    private let maxHistorySamples: Int = 60

    private init() {}

    deinit {
        timer?.cancel()
    }

    // MARK: - Lifecycle

    /// Begins 1-second throughput sampling.
    public func start() {
        guard !isRunning else { return }
        isRunning = true

        // Reset previous baseline so the first 1-second delta is clean
        previousSampleTime = nil
        previousInBytes = nil
        previousOutBytes = nil

        // Start path monitor to ensure primary interface is fresh
        ConnectionStatusService.shared.start()

        // Create 1-second repeating timer on private utility queue
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.isRunning else { return }
                self.sampleThroughput()
            }
        }
        timer.resume()
        self.timer = timer
    }

    /// Stops sampling and completely destroys the timer to guarantee zero CPU usage.
    public func stop() {
        guard isRunning else { return }
        isRunning = false

        // Cancel and nullify timer
        timer?.cancel()
        timer = nil

        previousSampleTime = nil
        previousInBytes = nil
        previousOutBytes = nil

        // Reset current rates
        downloadBytesPerSecond = 0.0
        uploadBytesPerSecond = 0.0
    }

    /// Convenience hook to toggle sampling based on view visibility.
    public func setVisibility(_ visible: Bool) {
        if visible {
            start()
        } else {
            stop()
        }
    }

    // MARK: - Sampling Logic

    private func sampleThroughput() {
        let now = Date()

        // 1. Obtain primary physical interface name
        let target = ConnectionStatusService.shared.primaryInterfaceName ?? "en0"
        let safeInterface = ConnectionStatusService.isVirtualInterface(target) ? "en0" : target

        // 2. Read physical byte counters from getifaddrs
        guard let (currentIn, currentOut) = Self.readByteCounters(for: safeInterface) else {
            return
        }

        self.currentInterfaceName = safeInterface

        // If we have a prior sample, calculate throughput
        if let prevTime = self.previousSampleTime,
           let prevIn = self.previousInBytes,
           let prevOut = self.previousOutBytes {

            let timeDelta = max(0.1, now.timeIntervalSince(prevTime))

            // Handle 32-bit counter rollover
            let inDelta = Self.calculateDelta(current: currentIn, previous: prevIn)
            let outDelta = Self.calculateDelta(current: currentOut, previous: prevOut)

            let downRate = Double(inDelta) / timeDelta
            let upRate = Double(outDelta) / timeDelta

            self.downloadBytesPerSecond = downRate
            self.uploadBytesPerSecond = upRate

            // Add sample to history
            let sample = ThroughputSample(
                timestamp: now,
                downloadBytesPerSecond: downRate,
                uploadBytesPerSecond: upRate
            )

            self.history.append(sample)
            if self.history.count > self.maxHistorySamples {
                self.history.removeFirst(self.history.count - self.maxHistorySamples)
            }
        }

        self.previousSampleTime = now
        self.previousInBytes = currentIn
        self.previousOutBytes = currentOut
    }

    // MARK: - Low-Level Byte Reading (BSD Darwin)

    /// Reads raw incoming and outgoing bytes for the given physical interface from BSD `if_data`.
    /// Returns `nil` if the interface is not active or has no AF_LINK record.
    nonisolated public static func readByteCounters(for interfaceName: String) -> (inBytes: UInt32, outBytes: UInt32)? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let name = String(cString: ptr.pointee.ifa_name)
            guard name == interfaceName else { continue }

            let family = ptr.pointee.ifa_addr.pointee.sa_family
            if family == UInt8(AF_LINK), let data = ptr.pointee.ifa_data {
                let ifData = data.assumingMemoryBound(to: if_data.self).pointee
                return (ifData.ifi_ibytes, ifData.ifi_obytes)
            }
        }

        return nil
    }

    /// Handles standard 32-bit integer rollover when network traffic wraps past 4GB.
    nonisolated private static func calculateDelta(current: UInt32, previous: UInt32) -> UInt64 {
        if current >= previous {
            return UInt64(current - previous)
        } else {
            // Rollover occurred past UInt32.max
            return UInt64((UInt64(UInt32.max) - UInt64(previous)) + UInt64(current) + 1)
        }
    }

    // MARK: - Formatted Presentation Helpers

    /// Human-readable download rate: e.g. "12.4 MB/s" or "350 KB/s".
    public var formattedDownloadSpeed: String {
        Self.formatSpeed(bytesPerSecond: downloadBytesPerSecond)
    }

    /// Human-readable upload rate: e.g. "1.2 MB/s" or "45 KB/s".
    public var formattedUploadSpeed: String {
        Self.formatSpeed(bytesPerSecond: uploadBytesPerSecond)
    }

    /// Maximum download speed in recent 60-sample window.
    public var peakHistoricalDownloadSpeed: Double {
        history.map(\.downloadBytesPerSecond).max() ?? 0.0
    }

    /// Maximum upload speed in recent 60-sample window.
    public var peakHistoricalUploadSpeed: Double {
        history.map(\.uploadBytesPerSecond).max() ?? 0.0
    }

    /// Formats bytes per second into standard rate format (B/s, KB/s, MB/s, GB/s).
    public static func formatSpeed(bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_073_741_824 {
            return String(format: "%.1f GB/s", bytesPerSecond / 1_073_741_824.0)
        } else if bytesPerSecond >= 1_048_576 {
            return String(format: "%.1f MB/s", bytesPerSecond / 1_048_576.0)
        } else if bytesPerSecond >= 1_024 {
            return String(format: "%.0f KB/s", bytesPerSecond / 1_024.0)
        } else if bytesPerSecond > 0 {
            return String(format: "%.0f B/s", bytesPerSecond)
        } else {
            return "0 B/s"
        }
    }
}
