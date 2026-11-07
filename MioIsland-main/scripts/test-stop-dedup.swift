#!/usr/bin/env swift
import Foundation

struct SessionState {
    var currentTurnNonce: Int = 0
    var lastCompletedTurnNonce: Int? = nil
    var lastStopAt: Date? = nil
}

enum HookEvent: String {
    case userPromptSubmit = "UserPromptSubmit"
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case stop = "Stop"
    case notification = "Notification"
}

func apply(_ event: HookEvent, to session: inout SessionState, now: Date) {
    switch event {
    case .userPromptSubmit, .preToolUse, .postToolUse:
        session.currentTurnNonce += 1
    default:
        break
    }
    if event == .stop {
        if session.lastCompletedTurnNonce == session.currentTurnNonce {
            return
        }
        if let prev = session.lastStopAt, now.timeIntervalSince(prev) < 3.0 {
            return
        }
        session.lastStopAt = now
        session.lastCompletedTurnNonce = session.currentTurnNonce
    }
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("✓ \(message)")
    } else {
        print("✗ \(message)")
        exit(1)
    }
}

var session = SessionState()
let t0 = Date(timeIntervalSince1970: 1_000)
apply(.userPromptSubmit, to: &session, now: t0)
apply(.stop, to: &session, now: t0.addingTimeInterval(10))
let firstStop = session.lastStopAt

apply(.notification, to: &session, now: t0.addingTimeInterval(20))
apply(.stop, to: &session, now: t0.addingTimeInterval(39))

check(session.lastStopAt == firstStop, "duplicate stop for same turn should not advance lastStopAt")

session = SessionState()
apply(.userPromptSubmit, to: &session, now: t0)
apply(.stop, to: &session, now: t0.addingTimeInterval(10))
let completedFirstTurn = session.lastStopAt
apply(.userPromptSubmit, to: &session, now: t0.addingTimeInterval(40))
apply(.stop, to: &session, now: t0.addingTimeInterval(50))

check(session.lastStopAt != completedFirstTurn, "new turn stop should still advance lastStopAt")
