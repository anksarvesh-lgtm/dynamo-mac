#!/usr/bin/env swift
import Foundation

func normalizedCompletionPanelInput(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("✓ \(message)")
    } else {
        print("✗ \(message)")
        exit(1)
    }
}

check(
    normalizedCompletionPanelInput("   \n\t  ") == nil,
    "blank draft does not produce a send payload"
)

check(
    normalizedCompletionPanelInput("  好的  ") == "好的",
    "leading and trailing whitespace is trimmed"
)

check(
    normalizedCompletionPanelInput("\n继续处理这个问题\n") == "继续处理这个问题",
    "surrounding newlines are trimmed"
)
