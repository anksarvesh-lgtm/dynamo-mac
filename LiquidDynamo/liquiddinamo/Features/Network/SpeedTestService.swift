//
//  SpeedTestService.swift
//  boringNotch
//
//  Created for Boring Notch
//

import Combine
import Foundation

// MARK: - Models

/// Individual speed test result record, persisted to local Application Support history.
public struct SpeedTestResult: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let interfaceName: String
    public let downloadMbps: Double
    public let uploadMbps: Double
    public let responsivenessRPM: Double
    public let idleLatencyMs: Double
    public let serverEndpoint: String?

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        interfaceName: String,
        downloadMbps: Double,
        uploadMbps: Double,
        responsivenessRPM: Double,
        idleLatencyMs: Double,
        serverEndpoint: String? = nil
    ) {
        self.id = id
        self.date = date
        self.interfaceName = interfaceName
        self.downloadMbps = downloadMbps
        self.uploadMbps = uploadMbps
        self.responsivenessRPM = responsivenessRPM
        self.idleLatencyMs = idleLatencyMs
        self.serverEndpoint = serverEndpoint
    }

    /// Evaluates responsiveness per Apple networkQuality rating brackets:
    /// - High: >= 1000 RPM (low latency under load)
    /// - Medium: 400 - 999 RPM
    /// - Low: < 400 RPM
    public var responsivenessRating: String {
        if responsivenessRPM >= 1000 {
            return "High"
        } else if responsivenessRPM >= 400 {
            return "Medium"
        } else {
            return "Low"
        }
    }
}

/// Execution status of the on-demand speed test.
public enum SpeedTestState: Equatable, Sendable {
    case idle
    case running(phase: String)
    case completed(SpeedTestResult)
    case cancelled
    case failed(error: String)
    case sandboxBlocked(message: String, proposedOptions: [String])
}

// MARK: - Private JSON Decodable Model

/// Raw output schema produced by `/usr/bin/networkQuality -c`.
private struct RawNetworkQualityOutput: Codable {
    let dl_throughput: Double?
    let ul_throughput: Double?
    let responsiveness: Double?
    let base_rtt: Double?
    let interface_name: String?
    let test_endpoint: String?
    let dl_bytes_transferred: Int?
    let ul_bytes_transferred: Int?
    let error_code: Int?
}

// MARK: - Speed Test Service

/// On-demand network speed test service using Apple's built-in `/usr/bin/networkQuality`.
///
/// Features:
/// - Strictly on-demand: Never starts automatically; only triggered when user clicks "Run speed test".
/// - Off-main-thread execution: Spawns `/usr/bin/networkQuality -c` with `-I <interface>` via `Process` in background.
/// - 60-second watchdog: Automatically terminates the child process if it exceeds 60 seconds.
/// - Full cancellation: Supports manual `cancelTest()`, immediately terminating the running process.
/// - Unit accuracy: Converts `networkQuality` JSON throughput (which is reported in **bits per second**) to Mbps (`/ 1_000_000.0`).
/// - Sandbox detection: Detects macOS App Sandbox confinement (`APP_SANDBOX_CONTAINER_ID` / `EPERM`).
///   If blocked, explicitly reports restriction and presents architectural options without silently falling back to 3rd-party servers.
/// - Local History: Persists the last 20 test results to `~/Library/Application Support/com.agrigence.liquiddynamo/SpeedTest/history.json`.
@MainActor
public final class SpeedTestService: ObservableObject {
    public static let shared = SpeedTestService()

    // MARK: - Published Properties

    @Published public private(set) var state: SpeedTestState = .idle
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var currentResult: SpeedTestResult? = nil
    @Published public private(set) var downloadSpeedMbps: Double? = nil
    @Published public private(set) var uploadSpeedMbps: Double? = nil
    @Published public private(set) var responsivenessRPM: Double? = nil
    @Published public private(set) var idleLatencyMs: Double? = nil
    @Published public private(set) var history: [SpeedTestResult] = []

    // MARK: - Private Properties

    private var currentProcess: Process?
    private var watchdogTask: Task<Void, Never>?
    private let historyMaxCount = 20

    private lazy var historyFileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let bundleID = Bundle.main.bundleIdentifier ?? "com.agrigence.liquiddynamo"
        let speedTestDir = appSupport
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("SpeedTest", isDirectory: true)

        try? FileManager.default.createDirectory(at: speedTestDir, withIntermediateDirectories: true)
        return speedTestDir.appendingPathComponent("history.json")
    }()

    // MARK: - Initialization

    private init() {
        loadHistory()
    }

    // MARK: - Public Actions

    /// Checks if the current app execution environment is restricted by macOS App Sandbox.
    nonisolated public static var isAppSandboxed: Bool {
        return ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
            || NSHomeDirectory().contains("/Containers/")
    }

    /// Triggers an on-demand speed test.
    ///
    /// - Parameter interface: Optional network interface name (e.g. "en0"). If nil, uses the primary active interface.
    public func startTest(interface: String? = nil) {
        guard !isRunning else {
            Logger.log("Speed test already in progress", category: .network)
            return
        }

        // Resolve interface to bind to
        let targetInterface = interface ?? ConnectionStatusService.shared.primaryInterfaceName

        isRunning = true
        state = .running(phase: "Starting test with Apple networkQuality...")
        Logger.log("Starting on-demand speed test (interface: \(targetInterface ?? "default"))", category: .network)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/networkQuality")

        var arguments = ["-c"]
        if let iface = targetInterface, !iface.isEmpty {
            arguments.append(contentsOf: ["-I", iface])
        }
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        self.currentProcess = process

        // 60-second watchdog timer: terminates process if running too long
        let watchdog = Task { [weak self, weak process] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard !Task.isCancelled else { return }
            guard let process = process, process.isRunning else { return }
            Logger.log("Speed test exceeded 60s timeout limit. Killing process.", category: .network)
            process.terminate()

            await MainActor.run { [weak self] in
                guard let self = self, self.isRunning else { return }
                self.isRunning = false
                self.currentProcess = nil
                self.state = .failed(error: "Speed test timed out after 60 seconds.")
            }
        }
        self.watchdogTask = watchdog

        let sandboxedEnv = Self.isAppSandboxed

        Task.detached(priority: .userInitiated) { [weak self, weak process] in
            guard let process = process else { return }

            do {
                try process.run()
            } catch {
                let nsError = error as NSError
                let blockedBySandbox = sandboxedEnv || (nsError.domain == NSPOSIXErrorDomain && nsError.code == 1)

                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.watchdogTask?.cancel()
                    self.watchdogTask = nil
                    self.isRunning = false
                    self.currentProcess = nil

                    if blockedBySandbox {
                        Logger.log("Process.run() blocked by macOS App Sandbox: \(error.localizedDescription)", category: .error)
                        self.state = .sandboxBlocked(
                            message: "Direct execution of /usr/bin/networkQuality is prohibited by macOS App Sandbox (Operation not permitted).",
                            proposedOptions: [
                                "Option 1: Route networkQuality execution through LiquidDynamoXPCHelper (unsandboxed XPC service).",
                                "Option 2: Disable App Sandbox in LiquidDynamo.entitlements for direct/Homebrew distribution.",
                                "Option 3: Run the test directly via Terminal: /usr/bin/networkQuality -c"
                            ]
                        )
                    } else {
                        Logger.log("Failed to launch /usr/bin/networkQuality: \(error.localizedDescription)", category: .error)
                        self.state = .failed(error: "Failed to launch networkQuality: \(error.localizedDescription)")
                    }
                }
                return
            }

            // Read output streams while process executes off the main thread
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let exitCode = process.terminationStatus
            let terminationReason = process.terminationReason

            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.watchdogTask?.cancel()
                self.watchdogTask = nil
                self.isRunning = false
                self.currentProcess = nil

                // Check if user manually cancelled or watchdog terminated
                if terminationReason == .uncaughtSignal && exitCode == 15 { // SIGTERM from cancel or timeout
                    if case .failed = self.state {
                        // Already handled by timeout watchdog
                        return
                    }
                    self.state = .cancelled
                    Logger.log("Speed test process cancelled", category: .network)
                    return
                }

                if exitCode != 0 {
                    let errMessage = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let displayError = (errMessage?.isEmpty ?? true) ? "Process exited with code \(exitCode)" : (errMessage ?? "")
                    Logger.log("Speed test failed with exit code \(exitCode): \(displayError)", category: .error)
                    self.state = .failed(error: displayError)
                    return
                }

                // Parse computer-readable JSON output
                guard let outputString = String(data: stdoutData, encoding: .utf8),
                      let jsonRangeStart = outputString.firstIndex(of: "{"),
                      let jsonRangeEnd = outputString.lastIndex(of: "}") else {
                    Logger.log("Could not locate valid JSON payload in networkQuality output", category: .error)
                    self.state = .failed(error: "Invalid output received from networkQuality tool.")
                    return
                }

                let jsonSubstring = String(outputString[jsonRangeStart...jsonRangeEnd])
                guard let validJsonData = jsonSubstring.data(using: .utf8) else {
                    self.state = .failed(error: "Failed to read networkQuality JSON buffer.")
                    return
                }

                do {
                    let decoded = try JSONDecoder().decode(RawNetworkQualityOutput.self, from: validJsonData)

                    // Note on units: Apple's networkQuality JSON throughput fields (dl_throughput, ul_throughput)
                    // are reported in bits per second (bps). We divide by 1,000,000.0 to convert to Mbps.
                    let dlBps = decoded.dl_throughput ?? 0.0
                    let ulBps = decoded.ul_throughput ?? 0.0
                    let dlMbps = dlBps / 1_000_000.0
                    let ulMbps = ulBps / 1_000_000.0
                    let responsivenessRPM = decoded.responsiveness ?? 0.0
                    let latencyMs = decoded.base_rtt ?? 0.0
                    let activeIface = decoded.interface_name ?? targetInterface ?? "en0"

                    let result = SpeedTestResult(
                        interfaceName: activeIface,
                        downloadMbps: dlMbps,
                        uploadMbps: ulMbps,
                        responsivenessRPM: responsivenessRPM,
                        idleLatencyMs: latencyMs,
                        serverEndpoint: decoded.test_endpoint
                    )

                    self.currentResult = result
                    self.downloadSpeedMbps = dlMbps
                    self.uploadSpeedMbps = ulMbps
                    self.responsivenessRPM = responsivenessRPM
                    self.idleLatencyMs = latencyMs
                    self.state = .completed(result)

                    self.saveResult(result)
                    Logger.log("Speed test completed: Downlink \(String(format: "%.2f", dlMbps)) Mbps, Uplink \(String(format: "%.2f", ulMbps)) Mbps, Responsiveness: \(String(format: "%.0f", responsivenessRPM)) RPM", category: .success)
                } catch {
                    Logger.log("Failed to decode networkQuality JSON: \(error.localizedDescription)", category: .error)
                    self.state = .failed(error: "JSON decode error: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Cancels any currently executing speed test immediately.
    public func cancelTest() {
        guard isRunning else { return }
        Logger.log("Cancelling ongoing speed test", category: .network)

        watchdogTask?.cancel()
        watchdogTask = nil

        if let proc = currentProcess, proc.isRunning {
            proc.terminate()
        }
        currentProcess = nil
        isRunning = false
        state = .cancelled
    }

    /// Clears all local test history from memory and disk.
    public func clearHistory() {
        history.removeAll()
        try? FileManager.default.removeItem(at: historyFileURL)
        Logger.log("Speed test history cleared", category: .network)
    }

    // MARK: - Persistence Helpers

    private func saveResult(_ result: SpeedTestResult) {
        history.insert(result, at: 0)
        if history.count > historyMaxCount {
            history = Array(history.prefix(historyMaxCount))
        }
        persistHistoryToDisk()
    }

    private func persistHistoryToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(history)
            try data.write(to: historyFileURL, options: .atomic)
        } catch {
            Logger.log("Failed to save speed test history to disk: \(error.localizedDescription)", category: .error)
        }
    }

    private func loadHistory() {
        guard FileManager.default.fileExists(atPath: historyFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: historyFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let saved = try decoder.decode([SpeedTestResult].self, from: data)
            self.history = Array(saved.prefix(historyMaxCount))
            if let latest = self.history.first {
                self.currentResult = latest
                self.downloadSpeedMbps = latest.downloadMbps
                self.uploadSpeedMbps = latest.uploadMbps
                self.responsivenessRPM = latest.responsivenessRPM
                self.idleLatencyMs = latest.idleLatencyMs
            }
        } catch {
            Logger.log("Failed to load speed test history from disk: \(error.localizedDescription)", category: .error)
        }
    }
}
