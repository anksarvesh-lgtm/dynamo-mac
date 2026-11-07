//
//  CompletionPanelInput.swift
//  ClaudeIsland
//
//  Shared normalization for direct text input in the completion panel.
//

import Foundation

enum CompletionPanelInput {
    static func normalizedDraft(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
