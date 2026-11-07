//
//  SummaryExtraction.swift
//  ClaudeIsland
//
//  Pure helper: strip trivial markdown (triple/single backticks, leading
//  `#`/`>`/whitespace including NBSP per line) + collapse whitespace for
//  the ≤3-line summary shown in CompletionPanelView. Spec §5.5 / §5.6.
//
//  ⚠️ Mirrored verbatim in scripts/test-summary-extraction.swift for the
//  standalone test runner — keep both bodies in sync when editing.
//

import Foundation

enum SummaryExtraction {
    static func extract(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        var s = raw
        s = s.replacingOccurrences(of: "```", with: "")
        s = s.replacingOccurrences(of: "`", with: "")
        s = s.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            var l = String(line)
            while let c = l.first, c == "#" || c == ">" || c.isWhitespace { l.removeFirst() }
            return l
        }.joined(separator: " ")
        let collapsed = s.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
                         .joined(separator: " ")
        return collapsed.trimmingCharacters(in: .whitespaces)
    }
}
