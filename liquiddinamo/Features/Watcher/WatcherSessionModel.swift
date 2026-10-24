//
//  WatcherSessionModel.swift
//  LiquidDynamo
//
//  Created for LiquidDynamo Watcher (AI Agent & Coding Session Monitor)
//

import Foundation
import SwiftUI

/// Recognized AI Coding Agents and Developer Assistants
public enum WatcherAgentKind: String, CaseIterable, Codable, Identifiable {
    case claudeCode = "claude"
    case antigravity = "antigravity"
    case cursor = "cursor"
    case codex = "codex"
    case geminiCLI = "gemini"
    case copilot = "copilot"
    case opencode = "opencode"
    case amp = "amp"
    case hermes = "hermes"
    case custom = "custom"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .antigravity: return "Antigravity"
        case .cursor: return "Cursor"
        case .codex: return "Codex"
        case .geminiCLI: return "Gemini CLI"
        case .copilot: return "GitHub Copilot"
        case .opencode: return "OpenCode"
        case .amp: return "Amp"
        case .hermes: return "Hermes"
        case .custom: return "AI Agent"
        }
    }

    public var iconName: String {
        switch self {
        case .claudeCode: return "sparkles"
        case .antigravity: return "bolt.shield.fill"
        case .cursor: return "chevron.left.forwardslash.chevron.right"
        case .codex: return "terminal.fill"
        case .geminiCLI: return "atom"
        case .copilot: return "cpu"
        case .opencode: return "curlybraces"
        case .amp: return "waveform.path"
        case .hermes: return "paperplane.fill"
        case .custom: return "gearshape.2.fill"
        }
    }

    public var themeColor: Color {
        switch self {
        case .claudeCode: return Color(red: 0.85, green: 0.45, blue: 0.25)
        case .antigravity: return Color.accentColor
        case .cursor: return Color(red: 0.2, green: 0.6, blue: 1.0)
        case .codex: return Color(red: 0.2, green: 0.8, blue: 0.6)
        case .geminiCLI: return Color(red: 0.35, green: 0.55, blue: 0.95)
        case .copilot: return Color(red: 0.4, green: 0.4, blue: 0.9)
        case .opencode: return Color.orange
        case .amp: return Color.yellow
        case .hermes: return Color.cyan
        case .custom: return Color.purple
        }
    }

    public static func match(from raw: String) -> WatcherAgentKind {
        let clean = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.contains("claude") { return .claudeCode }
        if clean.contains("antigravity") || clean.contains("agy") { return .antigravity }
        if clean.contains("cursor") { return .cursor }
        if clean.contains("codex") { return .codex }
        if clean.contains("gemini") { return .geminiCLI }
        if clean.contains("copilot") { return .copilot }
        if clean.contains("open") { return .opencode }
        if clean.contains("amp") { return .amp }
        if clean.contains("hermes") { return .hermes }
        return .custom
    }
}

/// Lifecycle execution states of an AI agent session
public enum WatcherSessionState: Equatable {
    case idle
    case thinking
    case working(tool: String)
    case permissionRequested(tool: String, details: String)
    case finished
    case error(message: String)

    public var statusLabel: String {
        switch self {
        case .idle: return "Idle"
        case .thinking: return "Thinking..."
        case .working(let tool): return "Running \(tool)"
        case .permissionRequested: return "Permission Required"
        case .finished: return "Finished"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    public var isActionable: Bool {
        if case .permissionRequested = self { return true }
        return false
    }
}

/// File modification diff statistics (+N lines added, -M lines deleted)
public struct WatcherDiffSummary: Equatable, Codable {
    public let fileName: String
    public let additions: Int
    public let deletions: Int

    public init(fileName: String, additions: Int = 0, deletions: Int = 0) {
        self.fileName = fileName
        self.additions = additions
        self.deletions = deletions
    }

    public var formattedSummary: String {
        "+\(additions) -\(deletions)"
    }
}

/// Represents an active or tracked AI coding session
public struct WatcherSession: Identifiable, Equatable {
    public let id: String
    public var agentKind: WatcherAgentKind
    public var customAgentName: String?
    public var state: WatcherSessionState
    public var prompt: String?
    public var activeTool: String?
    public var diffSummary: WatcherDiffSummary?
    public var terminalPID: pid_t?
    public var startedAt: Date
    public var lastActivityAt: Date

    public init(
        id: String = UUID().uuidString,
        agentKind: WatcherAgentKind = .claudeCode,
        customAgentName: String? = nil,
        state: WatcherSessionState = .idle,
        prompt: String? = nil,
        activeTool: String? = nil,
        diffSummary: WatcherDiffSummary? = nil,
        terminalPID: pid_t? = nil,
        startedAt: Date = Date(),
        lastActivityAt: Date = Date()
    ) {
        self.id = id
        self.agentKind = agentKind
        self.customAgentName = customAgentName
        self.state = state
        self.prompt = prompt
        self.activeTool = activeTool
        self.diffSummary = diffSummary
        self.terminalPID = terminalPID
        self.startedAt = startedAt
        self.lastActivityAt = lastActivityAt
    }

    public var displayName: String {
        customAgentName ?? agentKind.displayName
    }
}
