#!/usr/bin/env swift
import Foundation

enum ChatRole { case user, assistant }

struct ChatMessage {
    let role: ChatRole
    let textContent: String
}

func claudeImmediateFallback(messages: [ChatMessage], lastMessage: String?, lastMessageRole: String?) -> String {
    if let lastUserIndex = messages.lastIndex(where: { $0.role == .user }) {
        let afterLastUser = lastUserIndex + 1
        if afterLastUser < messages.count {
            for message in messages[afterLastUser...].reversed() {
                if message.role == .assistant,
                   !message.textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return message.textContent
                }
            }
        }
        return ""
    }
    if let assistant = messages.last(where: { $0.role == .assistant })?.textContent,
       !assistant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return assistant
    }
    if lastMessageRole == "assistant",
       let lastMessage,
       !lastMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return lastMessage
    }
    return ""
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
    claudeImmediateFallback(
        messages: [.init(role: .user, textContent: "你建议呢")],
        lastMessage: "你建议呢",
        lastMessageRole: "user"
    ).isEmpty,
    "does not fall back to last user prompt"
)

check(
    claudeImmediateFallback(
        messages: [.init(role: .assistant, textContent: "这是最后回复")],
        lastMessage: "旧内容",
        lastMessageRole: "assistant"
    ) == "这是最后回复",
    "prefers synced assistant chat item"
)

check(
    claudeImmediateFallback(
        messages: [],
        lastMessage: "这是 assistant fallback",
        lastMessageRole: "assistant"
    ) == "这是 assistant fallback",
    "uses conversation info only when role is assistant"
)

check(
    claudeImmediateFallback(
        messages: [
            .init(role: .assistant, textContent: "上一轮 assistant"),
            .init(role: .user, textContent: "好的"),
            .init(role: .assistant, textContent: "这一轮 assistant")
        ],
        lastMessage: "旧内容",
        lastMessageRole: "assistant"
    ) == "这一轮 assistant",
    "uses the assistant reply after the latest user turn"
)

check(
    claudeImmediateFallback(
        messages: [
            .init(role: .assistant, textContent: "上一轮 assistant"),
            .init(role: .user, textContent: "好的")
        ],
        lastMessage: "旧内容",
        lastMessageRole: "assistant"
    ).isEmpty,
    "does not fall back to previous-turn assistant while current turn has no reply yet"
)
