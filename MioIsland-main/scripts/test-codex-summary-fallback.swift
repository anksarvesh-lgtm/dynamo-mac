#!/usr/bin/env swift
import Foundation

enum Role { case user, assistant }

struct Message {
    let role: Role
    let text: String
}

func codexImmediateFallback(messages: [Message], lastMessage: String?, lastMessageRole: String?) -> String {
    var sawLatestUser = false
    for message in messages.reversed() {
        if message.role == .user {
            sawLatestUser = true
            break
        }
        if message.role == .assistant,
           !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return message.text
        }
    }
    if !sawLatestUser,
       lastMessageRole == "assistant",
       let lastMessage,
       !lastMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return lastMessage
    }
    return ""
}

func check(_ cond: @autoclosure () -> Bool, _ desc: String) {
    if cond() { print("✓ \(desc)") } else { print("✗ \(desc)"); exit(1) }
}

let userOnly = [Message(role: .user, text: "你建议呢")]
let mixed = [
    Message(role: .user, text: "你建议呢"),
    Message(role: .assistant, text: "先加一个已阅按钮"),
]
let staleAssistant = [
    Message(role: .assistant, text: "这版已经编译并启动"),
    Message(role: .user, text: "好的"),
    Message(role: .assistant, text: "好。"),
]
let waitingForReply = [
    Message(role: .assistant, text: "旧回答"),
    Message(role: .user, text: "好的"),
]
let sameTimestampOrdering = [
    Message(role: .assistant, text: "旧回答"),
    Message(role: .user, text: "好的"),
    Message(role: .assistant, text: "好。"),
]

check(codexImmediateFallback(messages: userOnly, lastMessage: "你建议呢", lastMessageRole: "user") == "",
      "user-only fallback should be empty")
check(codexImmediateFallback(messages: mixed, lastMessage: "你建议呢", lastMessageRole: "user") == "先加一个已阅按钮",
      "prefer latest assistant over last user prompt")
check(codexImmediateFallback(messages: staleAssistant, lastMessage: "好的", lastMessageRole: "user") == "好。",
      "ignore assistant text from previous turn")
check(codexImmediateFallback(messages: waitingForReply, lastMessage: "好的", lastMessageRole: "user") == "",
      "do not fall back to previous-turn assistant while waiting for current reply")
check(codexImmediateFallback(messages: sameTimestampOrdering, lastMessage: "好的", lastMessageRole: "user") == "好。",
      "use message order rather than timestamp ordering")
