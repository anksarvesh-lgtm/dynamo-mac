//
//  NetMergeEngine.swift
//  LiquidDynamo
//
//  Manager and lifecycle controller for the NetMerge multi-network link bonding engine.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import AppKit
import Combine
import Defaults
import Foundation

public final class NetMergeEngine: ObservableObject {
    public static let shared = NetMergeEngine()

    @Published public private(set) var serviceState: NetMergeServiceState = .stopped
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var isSystemWide: Bool = false
    @Published public private(set) var totalDownloadSpeedMbps: Double = 0.0
    @Published public private(set) var totalUploadSpeedMbps: Double = 0.0
    @Published public private(set) var activeAdapters: [NetMergeAdapterMetric] = []
    @Published public private(set) var totalActiveFlows: Int = 0
    @Published public private(set) var lastLogMessage: String = ""
    @Published public private(set) var socksListenAddress: String = "127.0.0.1"
    @Published public private(set) var socksListenPort: Int = 10888
    @Published public private(set) var detectedAdaptersCount: Int = 0

    private var process: Process?
    private var outputPipe: Pipe?
    private var outputHandle: FileHandle?
    private var readSource: DispatchSourceRead?
    private var buffer = Data()
    private var cancellables = Set<AnyCancellable>()

    private init() {
        self.socksListenPort = Defaults[.netMergeSocksPort]
        refreshDetectedAdapters()

        // Auto-start if enabled in settings
        if Defaults[.netMergeAutoStart] && Defaults[.netMergeEnabled] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.start()
            }
        }
    }

    deinit {
        stop()
    }

    // MARK: - Binary Resolution

    /// Locates the compiled Mach-O universal net-merge binary within the app bundle or standard paths.
    public func locateBinary() -> String? {
        let fileManager = FileManager.default

        // 1. App Bundle Resources
        if let resourcePath = Bundle.main.path(forResource: "net-merge", ofType: nil),
           fileManager.isExecutableFile(atPath: resourcePath) {
            return resourcePath
        }

        // 2. Main bundle Contents/Resources/net-merge
        let bundleResourcesPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Resources")
            .appendingPathComponent("net-merge").path
        if fileManager.isExecutableFile(atPath: bundleResourcesPath) {
            return bundleResourcesPath
        }

        // 3. Fallback relative to executable
        if let execPath = Bundle.main.executablePath {
            let relativePath = (execPath as NSString)
                .deletingLastPathComponent
                .appending("/../Resources/net-merge")
            let standardPath = (relativePath as NSString).standardizingPath
            if fileManager.isExecutableFile(atPath: standardPath) {
                return standardPath
            }
        }

        // 4. Local workspace debug path
        let workspaceDebugPath = "/Users/sarvesh/Desktop/LiquidDynamo-1.9.2/liquiddinamo/Resources/net-merge"
        if fileManager.isExecutableFile(atPath: workspaceDebugPath) {
            return workspaceDebugPath
        }

        // 5. System install fallback
        let systemPaths = ["/usr/local/bin/net-merge", "/opt/homebrew/bin/net-merge"]
        for path in systemPaths {
            if fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }

    // MARK: - Lifecycle Management

    /// Starts the NetMerge SOCKS5 connection bonding service.
    public func start(port: Int? = nil) {
        guard !isRunning else { return }

        let targetPort = port ?? Defaults[.netMergeSocksPort]
        self.socksListenPort = targetPort
        self.socksListenAddress = "127.0.0.1"

        guard let binaryPath = locateBinary() else {
            DispatchQueue.main.async {
                self.serviceState = .error
                self.lastLogMessage = "net-merge binary could not be found in application bundle."
            }
            return
        }

        // Ensure executable permissions
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryPath)

        DispatchQueue.main.async {
            self.serviceState = .starting
            self.lastLogMessage = "Starting NetMerge on port \(targetPort)..."
        }

        let newProcess = Process()
        newProcess.executableURL = URL(fileURLWithPath: binaryPath)
        newProcess.arguments = [
            "socks",
            "-listen", "127.0.0.1:\(targetPort)",
            "-stats", "1s",
            "-ipv6", Defaults[.netMergeIPv6Mode]
        ]

        let pipe = Pipe()
        newProcess.standardOutput = pipe
        newProcess.standardError = pipe

        newProcess.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isRunning = false
                self.serviceState = .stopped
                self.totalDownloadSpeedMbps = 0.0
                self.totalUploadSpeedMbps = 0.0
                self.totalActiveFlows = 0
                self.lastLogMessage = "NetMerge process stopped (exit code: \(proc.terminationStatus))"
            }
        }

        do {
            try newProcess.run()
            self.process = newProcess
            self.outputPipe = pipe
            self.startReadingOutput(pipe: pipe)

            DispatchQueue.main.async {
                self.isRunning = true
                self.serviceState = .active
                Defaults[.netMergeEnabled] = true
            }
        } catch {
            DispatchQueue.main.async {
                self.serviceState = .error
                self.lastLogMessage = "Failed to launch net-merge: \(error.localizedDescription)"
            }
        }
    }

    /// Stops the NetMerge service cleanly.
    public func stop() {
        guard isRunning || process != nil else { return }

        readSource?.cancel()
        readSource = nil

        if let proc = process, proc.isRunning {
            proc.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                if proc.isRunning {
                    kill(proc.processIdentifier, SIGKILL)
                }
            }
        }

        process = nil
        outputPipe = nil

        DispatchQueue.main.async {
            self.isRunning = false
            self.serviceState = .stopped
            self.totalDownloadSpeedMbps = 0.0
            self.totalUploadSpeedMbps = 0.0
            self.totalActiveFlows = 0
            Defaults[.netMergeEnabled] = false
        }
    }

    /// Toggles the running state of the NetMerge bonding service.
    public func toggle() {
        if isRunning {
            stop()
        } else {
            start()
        }
    }

    // MARK: - Output & Stats Parsing

    private func startReadingOutput(pipe: Pipe) {
        let handle = pipe.fileHandleForReading
        let fd = handle.fileDescriptor

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue.global(qos: .utility))
        self.readSource = source

        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            let data = handle.availableData
            guard !data.isEmpty else { return }

            self.buffer.append(data)
            self.processBuffer()
        }

        source.resume()
    }

    private func processBuffer() {
        while let newlineRange = buffer.range(of: Data([0x0A])) { // \n
            let lineData = buffer.subdata(in: 0..<newlineRange.lowerBound)
            buffer.removeSubrange(0..<newlineRange.upperBound)

            if let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !line.isEmpty {
                parseLogLine(line)
            }
        }
    }

    private func parseLogLine(_ line: String) {
        DispatchQueue.main.async {
            self.lastLogMessage = line
        }

        // Detection of active state
        if line.contains("SOCKS5 listening on") {
            DispatchQueue.main.async {
                self.serviceState = .active
            }
            return
        }

        // Header lines
        if line.starts(with: "---") || line.starts(with: "note:") || line.starts(with: "+") {
            return
        }

        // Format example from net-merge:
        // en0  v4 up  v6 up  link down  42.5 up  3.1 Mbit/s  via net-merge  42.5  active 8  total 24  w 1.00/1.00  failed 0
        let tokens = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard tokens.count >= 6 else { return }

        let ifaceName = tokens[0]
        guard ifaceName.starts(with: "en") || ifaceName.starts(with: "feth") || ifaceName.starts(with: "bridge") else {
            return
        }

        // Extract download speed: token preceding "up" or "Mbit/s"
        var downSpeed: Double = 0.0
        var upSpeed: Double = 0.0
        var activeFlows: Int = 0
        var totalFlows: Int = 0
        var weight: Double = 1.0
        var failedCount: Int = 0

        for i in 0..<tokens.count {
            if tokens[i] == "Mbit/s" && i >= 3 {
                upSpeed = Double(tokens[i - 1]) ?? 0.0
                downSpeed = Double(tokens[i - 3]) ?? 0.0
            }
            if tokens[i] == "active" && i + 1 < tokens.count {
                activeFlows = Int(tokens[i + 1]) ?? 0
            }
            if tokens[i] == "total" && i + 1 < tokens.count {
                totalFlows = Int(tokens[i + 1]) ?? 0
            }
            if tokens[i] == "failed" && i + 1 < tokens.count {
                failedCount = Int(tokens[i + 1]) ?? 0
            }
            if tokens[i] == "w" && i + 1 < tokens.count {
                let weightParts = tokens[i + 1].components(separatedBy: "/")
                weight = Double(weightParts.first ?? "1.0") ?? 1.0
            }
        }

        let isChecking = line.contains("checking")
        let isUsable = !line.contains("skip") && !line.contains("link down")

        let metric = NetMergeAdapterMetric(
            name: ifaceName,
            isUsable: isUsable,
            isChecking: isChecking,
            downloadSpeedMbps: downSpeed,
            uploadSpeedMbps: upSpeed,
            weight: weight,
            activeFlows: activeFlows,
            totalFlows: totalFlows,
            failedCount: failedCount
        )

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let index = self.activeAdapters.firstIndex(where: { $0.name == ifaceName }) {
                self.activeAdapters[index] = metric
            } else {
                self.activeAdapters.append(metric)
            }

            // Sum totals
            self.totalDownloadSpeedMbps = self.activeAdapters.map(\.downloadSpeedMbps).reduce(0, +)
            self.totalUploadSpeedMbps = self.activeAdapters.map(\.uploadSpeedMbps).reduce(0, +)
            self.totalActiveFlows = self.activeAdapters.map(\.activeFlows).reduce(0, +)

            let usableCount = self.activeAdapters.filter { $0.isUsable }.count
            if usableCount >= 2 {
                self.serviceState = .active
            } else if usableCount == 1 {
                self.serviceState = .degraded
            }
        }
    }

    // MARK: - Adapter Enumeration

    /// Scans network adapters by invoking `net-merge list`.
    public func refreshDetectedAdapters() {
        guard let binaryPath = locateBinary() else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = ["list"]

            let pipe = Pipe()
            process.standardOutput = pipe

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let output = String(data: data, encoding: .utf8) else { return }

                var count = 0
                var parsedList: [NetMergeAdapterMetric] = []

                for line in output.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.starts(with: "USE") {
                        count += 1
                        let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                        if parts.count >= 2 {
                            let name = parts[1]
                            var v4: String? = nil
                            var v6: String? = nil

                            if let v4Index = parts.firstIndex(of: "v4"), v4Index + 1 < parts.count {
                                v4 = parts[v4Index + 1]
                            }
                            if let v6Index = parts.firstIndex(of: "v6"), v6Index + 1 < parts.count {
                                v6 = parts[v6Index + 1]
                            }

                            parsedList.append(NetMergeAdapterMetric(name: name, ipv4: v4, ipv6: v6, isUsable: true))
                        }
                    }
                }

                DispatchQueue.main.async {
                    self?.detectedAdaptersCount = count
                    if self?.activeAdapters.isEmpty == true && !parsedList.isEmpty {
                        self?.activeAdapters = parsedList
                    }
                }
            } catch {
                // Ignore background list failure
            }
        }
    }

    /// Invokes system-wide bonding using macOS utun tunnel and administrator privileges.
    public func requestSystemWideBonding() {
        guard let binaryPath = locateBinary() else { return }

        let script = """
        do shell script "\(binaryPath) run > /dev/null 2>&1 &" with administrator privileges
        """

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
                DispatchQueue.main.async {
                    if error == nil {
                        self?.isSystemWide = true
                        self?.serviceState = .active
                    } else {
                        self?.lastLogMessage = "System-wide bonding permission cancelled or failed."
                    }
                }
            }
        }
    }
}
