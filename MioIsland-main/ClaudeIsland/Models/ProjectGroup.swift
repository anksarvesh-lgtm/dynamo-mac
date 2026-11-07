//
//  ProjectGroup.swift
//  ClaudeIsland
//
//  Groups sessions by working directory for the expanded session list.
//

import Foundation

struct ProjectGroup: Identifiable {
    let id: String  // project directory path (cwd)
    let name: String  // display name (last path component)
    var sessions: [SessionState]

    var activeCount: Int {
        sessions.filter { $0.phase != .idle && $0.phase != .ended }.count
    }

    var isArchivable: Bool {
        sessions.allSatisfy { $0.phase == .idle || $0.phase == .waitingForInput }
    }

    /// Groups sessions by their `cwd`, using the last path component as the project name.
    /// Groups are sorted by most recent activity (most active sessions first).
    static func group(sessions: [SessionState]) -> [ProjectGroup] {
        // Group sessions by cwd
        var grouped: [String: [SessionState]] = [:]
        for session in sessions {
            grouped[session.cwd, default: []].append(session)
        }

        // Build ProjectGroup instances
        var groups = grouped.map { (cwd, sessions) -> ProjectGroup in
            let name = URL(fileURLWithPath: cwd).lastPathComponent
            return ProjectGroup(id: cwd, name: name, sessions: sessions)
        }

        // Sort groups: most active first, then by most recent activity
        groups.sort { a, b in
            // Primary: groups with more active sessions first
            if a.activeCount != b.activeCount {
                return a.activeCount > b.activeCount
            }
            // Secondary: most recently active session in the group
            let latestA = a.sessions.map(\.lastActivity).max() ?? .distantPast
            let latestB = b.sessions.map(\.lastActivity).max() ?? .distantPast
            return latestA > latestB
        }

        return groups
    }
}
