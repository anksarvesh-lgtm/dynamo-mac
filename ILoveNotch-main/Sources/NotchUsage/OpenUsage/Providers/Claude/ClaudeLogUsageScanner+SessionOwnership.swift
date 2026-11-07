// SPDX-License-Identifier: MIT
// Adapted from OpenUsage (https://github.com/robinebers/openusage) at 4ce7887.
// Copyright (c) Robin Ebers and contributors. MIT License; see THIRD_PARTY_NOTICES.md.
// swift-format-ignore-file

import Foundation

extension ClaudeLogUsageScanner {
    /// Both direct agents and workflow agents belong to the session above `subagents/`.
    /// Resolve that session before reading bridge ownership or looking up Desktop's session index.
    /// Missing parents remain unattributed rather than treating an agent as an independent session.
    static func owningSessionFile(
        for file: JSONLScanning.DiscoveredFile,
        filesByPath: [String: JSONLScanning.DiscoveredFile]
    ) -> JSONLScanning.DiscoveredFile? {
        var directory = URL(fileURLWithPath: file.path).deletingLastPathComponent()
        while directory.path != "/", directory.lastPathComponent != "projects" {
            if directory.lastPathComponent == "subagents" {
                let parentPath = directory.deletingLastPathComponent().appendingPathExtension("jsonl").path
                return filesByPath[parentPath]
            }
            directory.deleteLastPathComponent()
        }
        return file
    }
}
