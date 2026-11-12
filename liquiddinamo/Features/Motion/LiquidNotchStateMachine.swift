//
//  LiquidNotchStateMachine.swift
//  LiquidDynamo
//
//  LiquidDynamo Core Team
//  Copyright © 2026 Agrigence. All rights reserved.
//

import Foundation

public struct LiquidPeekPayload: Equatable, Hashable, Sendable {
    public let id: String

    public init(id: String) {
        self.id = id
    }
}

public struct LiquidActivityID: Equatable, Hashable, Sendable {
    public let raw: String

    public init(raw: String) {
        self.raw = raw
    }
}

public enum LiquidHUDKind: Equatable, Hashable, Sendable {
    case volume
    case brightness
    case keyboardBacklight
    case capsLock
    case charging
}

public enum LiquidTransientKind: Equatable, Hashable, Sendable {
    case peek
    case hud
    case activity
}

public enum LiquidSwipeDirection: Equatable, Hashable, Sendable {
    case up
    case down
    case left
    case right
}

public enum LiquidPanelState: Equatable, Hashable, Sendable {
    case collapsed
    case peek(LiquidPeekPayload)
    case activity(LiquidActivityID)
    case hud(LiquidHUDKind)
    case expanded
}

public enum LiquidPanelEvent: Equatable, Hashable, Sendable {
    case hoverEnter
    case hoverExit
    case tap
    case swipe(LiquidSwipeDirection)
    case escape
    case clickAway
    case peekPosted(LiquidPeekPayload)
    case activityPosted(LiquidActivityID)
    case activityDismissed(LiquidActivityID)
    case hudEvent(LiquidHUDKind)
    case timeout(LiquidTransientKind)
}

public struct LiquidTransientDurations: Equatable, Sendable {
    public var peek: TimeInterval
    public var hud: TimeInterval
    public var activity: TimeInterval

    public init(peek: TimeInterval = 2.0, hud: TimeInterval = 1.5, activity: TimeInterval = 5.0) {
        self.peek = peek
        self.hud = hud
        self.activity = activity
    }

    public static let standard = LiquidTransientDurations()
}

public struct LiquidPanelTransition: Equatable, Sendable {
    public let next: LiquidPanelState
    public let autoDismissAfter: TimeInterval?

    public init(next: LiquidPanelState, autoDismissAfter: TimeInterval?) {
        self.next = next
        self.autoDismissAfter = autoDismissAfter
    }
}

public enum LiquidNotchStateMachine {
    public static func transition(
        from state: LiquidPanelState,
        on event: LiquidPanelEvent,
        pinned: Bool = false,
        durations: LiquidTransientDurations = .standard
    ) -> LiquidPanelTransition {
        switch event {
        case .hudEvent, .activityPosted, .peekPosted:
            return transitionForPost(event, from: state, durations: durations)
        case .activityDismissed(let id):
            return transitionForActivityDismissed(id, from: state)
        case .timeout(let kind):
            return transitionForTimeout(kind, from: state)
        case .hoverEnter, .tap:
            return transitionForOpen(event, from: state)
        case .escape, .hoverExit, .clickAway:
            return transitionForClose(event, from: state, pinned: pinned)
        case .swipe(let direction):
            return transitionForSwipe(direction, from: state, pinned: pinned)
        }
    }

    private static func transitionForPost(
        _ event: LiquidPanelEvent,
        from state: LiquidPanelState,
        durations: LiquidTransientDurations
    ) -> LiquidPanelTransition {
        switch event {
        case .hudEvent(let kind):
            if case .expanded = state {
                return stay(state)
            }
            return LiquidPanelTransition(next: .hud(kind), autoDismissAfter: durations.hud)
        case .activityPosted(let id):
            switch state {
            case .expanded, .hud:
                return stay(state)
            case .collapsed, .peek, .activity:
                return LiquidPanelTransition(next: .activity(id), autoDismissAfter: durations.activity)
            }
        case .peekPosted(let payload):
            switch state {
            case .collapsed, .peek:
                return LiquidPanelTransition(next: .peek(payload), autoDismissAfter: durations.peek)
            case .expanded, .hud, .activity:
                return stay(state)
            }
        default:
            return stay(state)
        }
    }

    private static func transitionForActivityDismissed(
        _ id: LiquidActivityID,
        from state: LiquidPanelState
    ) -> LiquidPanelTransition {
        if case .activity(let current) = state, current == id {
            return LiquidPanelTransition(next: .collapsed, autoDismissAfter: nil)
        }
        return stay(state)
    }

    private static func transitionForTimeout(
        _ kind: LiquidTransientKind,
        from state: LiquidPanelState
    ) -> LiquidPanelTransition {
        switch (state, kind) {
        case (.peek, .peek), (.hud, .hud), (.activity, .activity):
            return LiquidPanelTransition(next: .collapsed, autoDismissAfter: nil)
        default:
            return stay(state)
        }
    }

    private static func transitionForOpen(
        _ event: LiquidPanelEvent,
        from state: LiquidPanelState
    ) -> LiquidPanelTransition {
        switch event {
        case .hoverEnter:
            switch state {
            case .collapsed, .peek, .activity:
                return LiquidPanelTransition(next: .expanded, autoDismissAfter: nil)
            case .hud, .expanded:
                return stay(state)
            }
        case .tap:
            if case .expanded = state {
                return stay(state)
            }
            return LiquidPanelTransition(next: .expanded, autoDismissAfter: nil)
        default:
            return stay(state)
        }
    }

    private static func transitionForClose(
        _ event: LiquidPanelEvent,
        from state: LiquidPanelState,
        pinned: Bool
    ) -> LiquidPanelTransition {
        switch event {
        case .escape:
            if case .collapsed = state {
                return stay(state)
            }
            return LiquidPanelTransition(next: .collapsed, autoDismissAfter: nil)
        case .hoverExit, .clickAway:
            if case .expanded = state, !pinned {
                return LiquidPanelTransition(next: .collapsed, autoDismissAfter: nil)
            }
            return stay(state)
        default:
            return stay(state)
        }
    }

    private static func transitionForSwipe(
        _ direction: LiquidSwipeDirection,
        from state: LiquidPanelState,
        pinned: Bool
    ) -> LiquidPanelTransition {
        switch direction {
        case .down:
            if case .expanded = state {
                return stay(state)
            }
            return LiquidPanelTransition(next: .expanded, autoDismissAfter: nil)
        case .up:
            switch state {
            case .collapsed:
                return stay(state)
            case .expanded:
                return pinned ? stay(state) : LiquidPanelTransition(next: .collapsed, autoDismissAfter: nil)
            case .peek, .hud, .activity:
                return LiquidPanelTransition(next: .collapsed, autoDismissAfter: nil)
            }
        case .left, .right:
            return stay(state)
        }
    }

    private static func stay(_ state: LiquidPanelState) -> LiquidPanelTransition {
        LiquidPanelTransition(next: state, autoDismissAfter: nil)
    }
}
