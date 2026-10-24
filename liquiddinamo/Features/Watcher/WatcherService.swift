//
//  WatcherService.swift
//  LiquidDynamo
//
//  Created for LiquidDynamo Watcher (AI Agent & Coding Session Monitor)
//

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

/// Background coordinator and IPC server that monitors active AI coding agent sessions
/// (Claude Code, Antigravity, Cursor, Codex, Gemini CLI, etc.) via Unix domain socket hooks.
@MainActor
public final class WatcherService: ObservableObject {
    public static let shared = WatcherService()

    @Published public private(set) var activeSessions: [WatcherSession] = []
    @Published public private(set) var primarySession: WatcherSession? = nil
    @Published public private(set) var isListening: Bool = false
    @Published public var isExpandedCardOpen: Bool = false

    private var serverSource: DispatchSourceRead?
    private var clientSources: [Int32: DispatchSourceRead] = [:]
    private var pendingPermissionClients: [String: Int32] = [:] // sessionId: clientFD
    private var serverFD: Int32 = -1

    public let primarySocketPath: String = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("LiquidDynamo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("watcher.sock").path
    }()

    public let fallbackSocketPath: String = "/tmp/liquid_watcher.sock"

    private init() {
        startServer()
    }

    deinit {
        // Shared singleton exists for process duration
    }

    // MARK: - Server Lifecycle

    public func startServer() {
        guard serverFD == -1 else { return }

        // Create socket
        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            print("[Watcher] Failed to create socket: \(errno)")
            return
        }

        // Set non-blocking
        var flags = fcntl(serverFD, F_GETFL, 0)
        _ = fcntl(serverFD, F_SETFL, flags | O_NONBLOCK)

        // Bind to primary socket path
        unlink(primarySocketPath)
        unlink(fallbackSocketPath)

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        _ = primarySocketPath.withCString {
            strncpy(&addr.sun_path.0, $0, maxLen - 1)
        }

        let bindRes = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(serverFD, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        if bindRes < 0 {
            print("[Watcher] Failed to bind to \(primarySocketPath), errno: \(errno)")
            close(serverFD)
            serverFD = -1
            return
        }

        // Create symlink for fallback path
        try? FileManager.default.createSymbolicLink(atPath: fallbackSocketPath, withDestinationPath: primarySocketPath)

        // Listen with backlog
        if listen(serverFD, 16) < 0 {
            print("[Watcher] Listen failed: \(errno)")
            close(serverFD)
            serverFD = -1
            return
        }

        // Create dispatch source on main queue for zero-idle CPU socket polling
        let currentFD = serverFD
        let source = DispatchSource.makeReadSource(fileDescriptor: serverFD, queue: DispatchQueue.main)
        source.setEventHandler { [weak self] in
            self?.handleIncomingConnection()
        }
        source.setCancelHandler {
            close(currentFD)
        }
        source.resume()
        self.serverSource = source
        self.isListening = true
        print("[Watcher] IPC Server actively listening on \(primarySocketPath)")
    }

    public func stopServer() {
        serverSource?.cancel()
        serverSource = nil
        serverFD = -1

        for (_, src) in clientSources {
            src.cancel()
        }
        clientSources.removeAll()
        pendingPermissionClients.removeAll()

        unlink(primarySocketPath)
        unlink(fallbackSocketPath)
        isListening = false
    }

    // MARK: - Connection & IPC Handling

    private func handleIncomingConnection() {
        var clientAddr = sockaddr_un()
        var addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)

        while true {
            let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    accept(serverFD, sa, &addrLen)
                }
            }

            if clientFD < 0 {
                break // No more incoming connections
            }

            // Set client non-blocking
            let flags = fcntl(clientFD, F_GETFL, 0)
            _ = fcntl(clientFD, F_SETFL, flags | O_NONBLOCK)

            setupClientSource(fd: clientFD)
        }
    }

    private func setupClientSource(fd: Int32) {
        let clientSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue.global(qos: .utility))
        var buffer = Data()

        clientSource.setEventHandler { [weak self] in
            var readBuf = [UInt8](repeating: 0, count: 4096)
            let bytesRead = read(fd, &readBuf, readBuf.count)

            if bytesRead > 0 {
                buffer.append(readBuf, count: bytesRead)
                // Process lines
                while let newlineRange = buffer.range(of: Data([0x0A])) { // \n
                    let lineData = buffer.subdata(in: 0..<newlineRange.lowerBound)
                    buffer.removeSubrange(0..<newlineRange.upperBound)
                    if let jsonStr = String(data: lineData, encoding: .utf8), !jsonStr.trimmingCharacters(in: .whitespaces).isEmpty {
                        Task { @MainActor [weak self] in
                            self?.processIncomingPayload(jsonStr, clientFD: fd)
                        }
                    }
                }
            } else if bytesRead == 0 {
                // EOF
                clientSource.cancel()
            }
        }

        clientSource.setCancelHandler {
            close(fd)
        }

        clientSources[fd] = clientSource
        clientSource.resume()
    }

    // MARK: - JSON Event Parsing

    public func processIncomingPayload(_ jsonString: String, clientFD: Int32? = nil) {
        guard let data = jsonString.data(using: .utf8),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return
        }

        let eventName = (dict["hook_event_name"] as? String) ?? (dict["event"] as? String) ?? "Unknown"
        let sessionId = (dict["session_id"] as? String) ?? "default"
        let agentRaw = (dict["coucou_agent"] as? String) ?? (dict["agent"] as? String) ?? "claude"
        let prompt = (dict["prompt"] as? String) ?? (dict["message"] as? String)
        let toolName = (dict["tool_name"] as? String) ?? (dict["tool"] as? String)
        let agentKind = WatcherAgentKind.match(from: agentRaw)

        if let fd = clientFD {
            pendingPermissionClients[sessionId] = fd
        }

        handleAgentEvent(
            sessionId: sessionId,
            agentKind: agentKind,
            customName: agentRaw != agentKind.rawValue ? agentRaw : nil,
            eventName: eventName,
            prompt: prompt,
            toolName: toolName,
            rawDict: dict
        )
    }

    private func handleAgentEvent(
        sessionId: String,
        agentKind: WatcherAgentKind,
        customName: String?,
        eventName: String,
        prompt: String?,
        toolName: String?,
        rawDict: [String: Any]
    ) {
        var session = activeSessions.first(where: { $0.id == sessionId }) ?? WatcherSession(
            id: sessionId,
            agentKind: agentKind,
            customAgentName: customName
        )

        session.lastActivityAt = Date()
        if let p = prompt { session.prompt = p }
        if let t = toolName { session.activeTool = t }

        switch eventName {
        case "SessionStart":
            session.state = .idle

        case "UserPromptSubmit":
            session.state = .thinking

        case "PreToolUse":
            let tool = toolName ?? "tool"
            session.state = .working(tool: tool)

            // Parse diff if file edit
            if let filePath = rawDict["file_path"] as? String {
                let add = (rawDict["additions"] as? Int) ?? 0
                let del = (rawDict["deletions"] as? Int) ?? 0
                session.diffSummary = WatcherDiffSummary(fileName: (filePath as NSString).lastPathComponent, additions: add, deletions: del)
            }

        case "PostToolUse", "PostToolUseFailure":
            session.state = .working(tool: toolName ?? "task")

        case "PermissionRequest":
            let tool = toolName ?? "Command"
            let details = (rawDict["command"] as? String) ?? (rawDict["details"] as? String) ?? "Requires authorization"
            session.state = .permissionRequested(tool: tool, details: details)
            triggerPermissionAlert(session: session, tool: tool, details: details)

        case "Stop":
            session.state = .finished
            scheduleSessionDismissal(sessionId: sessionId, delay: 5.0)

        case "StopFailure":
            let err = (rawDict["error"] as? String) ?? "Failed execution"
            session.state = .error(message: err)

        case "SessionEnd":
            removeSession(sessionId: sessionId)
            return

        default:
            session.state = .working(tool: eventName)
        }

        updateSession(session)
    }

    private func updateSession(_ session: WatcherSession) {
        if let idx = activeSessions.firstIndex(where: { $0.id == session.id }) {
            activeSessions[idx] = session
        } else {
            activeSessions.append(session)
        }
        recalculatePrimarySession()
    }

    private func removeSession(sessionId: String) {
        activeSessions.removeAll(where: { $0.id == sessionId })
        pendingPermissionClients.removeValue(forKey: sessionId)
        recalculatePrimarySession()
    }

    private func recalculatePrimarySession() {
        // Priority: 1. Permission requested, 2. Working, 3. Thinking, 4. Most recent
        self.primarySession = activeSessions.sorted { s1, s2 in
            if s1.state.isActionable != s2.state.isActionable {
                return s1.state.isActionable && !s2.state.isActionable
            }
            return s1.lastActivityAt > s2.lastActivityAt
        }.first
    }

    private func scheduleSessionDismissal(sessionId: String, delay: Double) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            self?.removeSession(sessionId: sessionId)
        }
    }

    // MARK: - Permission Decision Actions

    public func respondToPermission(sessionId: String, allow: Bool, always: Bool = false) {
        guard let fd = pendingPermissionClients[sessionId] else { return }

        let decision = allow ? (always ? "always" : "allow") : "deny"
        let responseJson = "{\"decision\":\"\(decision)\"}\n"
        if let data = responseJson.data(using: .utf8) {
            _ = data.withUnsafeBytes { ptr in
                write(fd, ptr.baseAddress, data.count)
            }
        }

        if var session = activeSessions.first(where: { $0.id == sessionId }) {
            session.state = allow ? .working(tool: session.activeTool ?? "Action") : .idle
            updateSession(session)
        }

        IslandController.shared.dismissAlert()
    }

    private func triggerPermissionAlert(session: WatcherSession, tool: String, details: String) {
        let payload = AlertPayload(
            id: "watcher.permission.\(session.id)",
            kind: .custom(title: "\(session.displayName) Permission", subtitle: "\(tool): \(details)", icon: "shield.checkered"),
            title: "\(session.displayName) Authorization",
            subtitle: "\(tool) • \(details)",
            iconName: "shield.checkered",
            iconColor: .orange,
            dwellDuration: 12.0,
            action: { [weak self] in
                self?.isExpandedCardOpen = true
                IslandController.shared.setExpanded(view: .home)
            }
        )
        IslandController.shared.showAlert(payload: payload)
    }

    // MARK: - Testing Simulator

    public func simulateAgentActivity(agent: WatcherAgentKind = .claudeCode, tool: String = "edit file", diff: WatcherDiffSummary? = WatcherDiffSummary(fileName: "ContentView.swift", additions: 14, deletions: 2)) {
        let sid = "sim-\(agent.rawValue)"
        var session = WatcherSession(
            id: sid,
            agentKind: agent,
            state: .working(tool: tool),
            prompt: "Refactor compact layout",
            activeTool: tool,
            diffSummary: diff
        )
        updateSession(session)

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            session.state = .finished
            self?.updateSession(session)
            self?.scheduleSessionDismissal(sessionId: sid, delay: 3.5)
        }
    }
}
