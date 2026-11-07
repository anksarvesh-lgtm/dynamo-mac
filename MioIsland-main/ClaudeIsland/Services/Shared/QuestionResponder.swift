//
//  QuestionResponder.swift
//  ClaudeIsland
//
//  Delivers AskUserQuestion answers to Claude Code.
//  Primary: hook socket response. Fallback: tmux send-keys.
//

import Foundation

actor QuestionResponder {
    static let shared = QuestionResponder()

    private init() {}

    /// Send answer via tmux send-keys as fallback.
    /// Maps the selected option to its 1-based index in the CLI list.
    func sendViaTmux(session: SessionState, optionIndex: Int) async {
        guard let tty = session.tty else { return }

        let keys = "\(optionIndex)"
        let tmuxPath = await TmuxPathFinder.shared.getTmuxPath() ?? "/opt/homebrew/bin/tmux"

        do {
            // Find the tmux pane for this tty
            let panes = try await ProcessExecutor.shared.run(tmuxPath, arguments: [
                "list-panes", "-a", "-F", "#{pane_tty} #{pane_id}"
            ])
            let targetPane = panes.split(separator: "\n")
                .first { $0.contains(tty) }?
                .split(separator: " ")
                .last
                .map(String.init)

            guard let paneId = targetPane else { return }

            _ = try await ProcessExecutor.shared.run(tmuxPath, arguments: [
                "send-keys", "-t", paneId, "-l", keys
            ])
            _ = try await ProcessExecutor.shared.run(tmuxPath, arguments: [
                "send-keys", "-t", paneId, "Enter"
            ])
        } catch {
            DebugLogger.log("QuestionResponder", "tmux fallback failed: \(error)")
        }
    }
}
