//
//  NetworkSpeedProvider.swift
//  LiquidDynamo
//
//  Real-time network speed provider for notch wings.
//  Measures per-second bytes in/out from low-level Darwin interface counters via getifaddrs.
//  Ignores loopback, formats as KB/s / MB/s, and starts/stops on demand to maintain ~0% idle CPU.
//

import Combine
import Darwin
import Foundation
import SwiftUI

@MainActor
public final class NetworkSpeedProvider: ObservableObject {
    public static let shared = NetworkSpeedProvider()

    @Published public private(set) var bytesInPerSecond: Double = 0.0
    @Published public private(set) var bytesOutPerSecond: Double = 0.0
    @Published public private(set) var isRunning: Bool = false

    private var timer: DispatchSourceTimer?
    private var previousTime: Date?
    private var previousInBytes: UInt32?
    private var previousOutBytes: UInt32?
    private let queue = DispatchQueue(label: "com.agrigence.liquiddynamo.networkspeed", qos: .utility)

    private init() {}

    deinit {
        timer?.cancel()
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true

        previousTime = nil
        previousInBytes = nil
        previousOutBytes = nil

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.isRunning else { return }
                self.sampleSpeed()
            }
        }
        timer.resume()
        self.timer = timer
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        timer?.cancel()
        timer = nil

        previousTime = nil
        previousInBytes = nil
        previousOutBytes = nil
        bytesInPerSecond = 0.0
        bytesOutPerSecond = 0.0
    }

    private func sampleSpeed() {
        let now = Date()
        guard let (currentIn, currentOut) = Self.readAggregateCounters() else { return }

        if let prevTime = previousTime,
           let prevIn = previousInBytes,
           let prevOut = previousOutBytes {
            let elapsed = max(0.2, now.timeIntervalSince(prevTime))
            let inDelta = Self.calculateDelta(current: currentIn, previous: prevIn)
            let outDelta = Self.calculateDelta(current: currentOut, previous: prevOut)

            self.bytesInPerSecond = Double(inDelta) / elapsed
            self.bytesOutPerSecond = Double(outDelta) / elapsed
        }

        previousTime = now
        previousInBytes = currentIn
        previousOutBytes = currentOut
    }

    // MARK: - BSD Darwin getifaddrs (Ignoring Loopback)

    nonisolated private static func readAggregateCounters() -> (inBytes: UInt32, outBytes: UInt32)? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var totalIn: UInt32 = 0
        var totalOut: UInt32 = 0
        var foundAny = false

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            // Skip loopback interfaces entirely (lo0)
            if (flags & IFF_LOOPBACK) != 0 { continue }
            // Must be up and running
            if (flags & IFF_UP) == 0 || (flags & IFF_RUNNING) == 0 { continue }

            let name = String(cString: ptr.pointee.ifa_name)
            // Also ignore known virtual tunnel/bridge devices to prevent double counting
            if name.hasPrefix("lo") || name.hasPrefix("utun") || name.hasPrefix("bridge") || name.hasPrefix("awdl") {
                continue
            }

            let family = ptr.pointee.ifa_addr.pointee.sa_family
            if family == UInt8(AF_LINK), let data = ptr.pointee.ifa_data {
                let ifData = data.assumingMemoryBound(to: if_data.self).pointee
                totalIn &+= ifData.ifi_ibytes
                totalOut &+= ifData.ifi_obytes
                foundAny = true
            }
        }

        return foundAny ? (totalIn, totalOut) : nil
    }

    nonisolated private static func calculateDelta(current: UInt32, previous: UInt32) -> UInt32 {
        if current >= previous {
            return current - previous
        } else {
            // Handle 32-bit integer overflow/rollover
            return (UInt32.max - previous) &+ current &+ 1
        }
    }

    // MARK: - Formatting Helpers

    public var formattedDownload: String {
        Self.formatRate(bytesInPerSecond)
    }

    public var formattedUpload: String {
        Self.formatRate(bytesOutPerSecond)
    }

    public var formattedCombined: String {
        let down = Self.formatCompactRate(bytesInPerSecond)
        let up = Self.formatCompactRate(bytesOutPerSecond)
        return "↓\(down) ↑\(up)"
    }

    public static func formatRate(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_048_576 {
            return String(format: "%.1f MB/s", bytesPerSec / 1_048_576.0)
        } else if bytesPerSec >= 1024 {
            return String(format: "%.0f KB/s", bytesPerSec / 1024.0)
        } else {
            return "0 KB/s"
        }
    }

    public static func formatCompactRate(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_048_576 {
            return String(format: "%.1fM", bytesPerSec / 1_048_576.0)
        } else if bytesPerSec >= 1024 {
            return String(format: "%.0fK", bytesPerSec / 1024.0)
        } else {
            return "0K"
        }
    }
}
