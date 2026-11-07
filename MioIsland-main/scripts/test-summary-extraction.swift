#!/usr/bin/env swift
import Foundation

// === Copy of extractSummary (keep in sync with SummaryExtraction.swift) ===

func extractSummary(_ raw: String?) -> String {
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

// === tests ===
var passed = 0, failed = 0
func check(_ cond: @autoclosure () -> Bool, _ desc: String, line: UInt = #line) {
    if cond() { passed += 1; print("  ✓ \(desc)") }
    else { failed += 1; print("  ✗ \(desc) (line \(line))") }
}

check(extractSummary(nil) == "", "nil → empty")
check(extractSummary("") == "", "empty → empty")
check(extractSummary("hello world") == "hello world", "plain passthrough")
check(extractSummary("`foo` bar") == "foo bar", "single backtick stripped")
check(extractSummary("```\ncode\n```") == "code", "fence stripped")
check(extractSummary("# Title\ntext") == "Title text", "heading stripped")
check(extractSummary("\u{00A0}# Title\ntext") == "Title text", "NBSP-prefixed heading stripped")
check(extractSummary("> quote\ntext") == "quote text", "quote stripped")
check(extractSummary("multi\n  \n    space") == "multi space", "whitespace collapsed")

print("\n\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
