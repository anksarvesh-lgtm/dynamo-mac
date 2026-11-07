//
//  AgentSocketService.swift
//  LiquidDynamo
//
//  Merged from MioIsland: Real-time Unix domain socket server for AI developer agents
//  (Claude Code, Cursor, Agy, CLI tools) with in-notch live status & permission approval.
//

import Combine
import Foundation

public struct AgentPermissionRequest: Identifiable, Equatable {
    public let id: String
    public let agentName: String
    public let toolName: String
    public let command: String
    public let summary: String
    public let timestamp: Date

    public init(id: String = UUID().uuidString, agentName: String = "Coding Agent", toolName: String = "Terminal", command: String = "", summary: String = "") {
        self.id = id
        self.agentName = agentName
        self.toolName = toolName
        self.command = command
        self.summary = summary
        self.timestamp = Date()
    }
}

public enum AgentState: String {
    case idle = "Idle"
    case thinking = "Thinking"
    case toolUse = "Tool Execution"
    case awaitingPermission = "Needs Approval"
    case finished = "Finished"
    case error = "Error"
}

@MainActor
public final class AgentSocketService: ObservableObject {
    public static let shared = AgentSocketService()

    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var activeAgentName: String = "Claude Code"
    @Published public private(set) var state: AgentState = .idle
    @Published public private(set) var currentActivity: String = "Ready for agent sessions"
    @Published public private(set) var activeSessionCost: Double = 0.0
    @Published public private(set) var pendingRequest: AgentPermissionRequest? = nil
    @Published public private(set) var recentLogs: [String] = []

    private var serverSource: DispatchSourceRead?
    private var clientFileDescriptor: Int32 = -1
    private let primarySocketPath = "/tmp/liquiddynamo_agent.sock"
    private let fallbackSocketPath = "/tmp/codeisland.sock"

    private init() {
        startSocketServer()
    }

    public func startSocketServer() {
        setupListener(at: primarySocketPath)
    }

    private func setupListener(at path: String) {
        unlink(path)

        let serverFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFd >= 0 else { return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            path.withCString { cstr in
                _ = strncpy(ptr, cstr, maxLen - 1)
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(serverFd, sa, addrLen)
            }
        }

        guard bindResult == 0, listen(serverFd, 5) == 0 else {
            close(serverFd)
            return
        }

        chmod(path, 0o777)

        let source = DispatchSource.makeReadSource(fileDescriptor: serverFd, queue: DispatchQueue.global(qos: .userInitiated))
        source.setEventHandler { [weak self] in
            var clientAddr = sockaddr_un()
            var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)
            let clientFd = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    accept(serverFd, sa, &clientLen)
                }
            }
            if clientFd >= 0 {
                Task { @MainActor [weak self] in
                    self?.handleNewConnection(clientFd)
                }
            }
        }
        source.resume()
        self.serverSource = source
    }

    private func handleNewConnection(_ clientFd: Int32) {
        self.clientFileDescriptor = clientFd
        self.isConnected = true
        self.appendLog("Connected to agent process.")

        let readSource = DispatchSource.makeReadSource(fileDescriptor: clientFd, queue: DispatchQueue.global(qos: .userInitiated))
        readSource.setEventHandler { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = read(clientFd, &buffer, buffer.count)
            if bytesRead > 0 {
                let data = Data(buffer[0..<bytesRead])
                Task { @MainActor [weak self] in
                    self?.processIncomingData(data)
                }
            } else {
                readSource.cancel()
                close(clientFd)
                Task { @MainActor [weak self] in
                    self?.isConnected = false
                    self?.appendLog("Agent disconnected.")
                }
            }
        }
        readSource.resume()
    }

    private func processIncomingData(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if let string = String(data: data, encoding: .utf8) {
                appendLog(string.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return
        }

        let type = json["type"] as? String ?? ""
        if let agent = json["agent"] as? String {
            self.activeAgentName = agent
        }

        switch type {
        case "status":
            if let st = json["status"] as? String {
                self.state = AgentState(rawValue: st) ?? .thinking
            }
            if let act = json["action"] as? String {
                self.currentActivity = act
                appendLog("▶ \(act)")
            }
            if let cost = json["cost"] as? Double {
                self.activeSessionCost = cost
            }

        case "ask_permission":
            self.state = .awaitingPermission
            let req = AgentPermissionRequest(
                id: json["id"] as? String ?? UUID().uuidString,
                agentName: activeAgentName,
                toolName: json["tool"] as? String ?? "Tool",
                command: json["command"] as? String ?? "",
                summary: json["summary"] as? String ?? "Agent requested permission"
            )
            self.pendingRequest = req
            appendLog("⚠️ Permission requested for \(req.toolName)")

        case "clear":
            self.pendingRequest = nil
            self.state = .idle
            self.currentActivity = "Agent session idle"

        default:
            break
        }
    }

    public func respondToPermission(allowed: Bool) {
        guard let req = pendingRequest else { return }
        let reply = ["id": req.id, "status": allowed ? "approved" : "denied"]
        if let data = try? JSONSerialization.data(withJSONObject: reply), clientFileDescriptor >= 0 {
            _ = data.withUnsafeBytes { ptr in
                write(clientFileDescriptor, ptr.baseAddress, data.count)
            }
        }
        appendLog(allowed ? "✅ Approved \(req.toolName)" : "❌ Denied \(req.toolName)")
        self.pendingRequest = nil
        self.state = allowed ? .toolUse : .idle
    }

    public func simulateDemoRequest() {
        self.isConnected = true
        self.activeAgentName = "Claude Code"
        self.state = .awaitingPermission
        self.currentActivity = "Editing Island shader parameters"
        self.pendingRequest = AgentPermissionRequest(
            id: UUID().uuidString,
            agentName: "Claude Code",
            toolName: "Terminal / Bash",
            command: "git commit -m 'feat: merge all island engines'",
            summary: "Commit staged Dynamic Island enhancements to local repository"
        )
    }

    private func appendLog(_ entry: String) {
        recentLogs.append("[\(Date().formatted(date: .omitted, time: .standard))] \(entry)")
        if recentLogs.count > 30 {
            recentLogs.removeFirst()
        }
    }
}

