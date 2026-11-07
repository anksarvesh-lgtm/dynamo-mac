#!/usr/bin/env swift
import Foundation

enum ItemType {
    case user(String)
    case assistant(String)
}

struct Item {
    let id: String
    let type: ItemType
    let timestamp: Date
}

func latestAssistantResponse(in items: [Item]) -> String {
    for item in items.reversed() {
        if case .user = item.type {
            break
        }
        if case .assistant(let text) = item.type,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
    }
    return ""
}

func unstableSort(_ items: [Item]) -> [Item] {
    items.sorted { $0.timestamp < $1.timestamp }
}

func stableSort(_ items: [Item]) -> [Item] {
    items.enumerated().sorted { lhs, rhs in
        if lhs.element.timestamp != rhs.element.timestamp {
            return lhs.element.timestamp < rhs.element.timestamp
        }
        return lhs.offset < rhs.offset
    }.map(\.element)
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("✓ \(message)")
    } else {
        print("✗ \(message)")
        exit(1)
    }
}

let t = Date()
let items = [
    Item(id: "assistant-old", type: .assistant("上一轮 assistant"), timestamp: t),
    Item(id: "user-new", type: .user("好的"), timestamp: t),
    Item(id: "assistant-new", type: .assistant("这一轮 assistant"), timestamp: t),
]

let stable = stableSort(items)
check(
    latestAssistantResponse(in: stable) == "这一轮 assistant",
    "stable sort preserves source order for same-timestamp messages"
)

let unstable = unstableSort(items)
let unstableResult = latestAssistantResponse(in: unstable)
check(
    unstableResult == "这一轮 assistant",
    "plain timestamp sort should also preserve current-turn assistant"
)
