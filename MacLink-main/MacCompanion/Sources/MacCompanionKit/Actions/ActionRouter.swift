// SPDX-License-Identifier: MIT
import Foundation

public enum GestureAction: String, Codable, Sendable, CaseIterable {
    case missionControl = "Mission Control"
    case appExpose = "App Exposé"
    case previousSpace = "Previous Space"
    case nextSpace = "Next Space"
    case showDesktop = "Show Desktop"
    case launchpad = "Launchpad"
    case lockScreen = "Lock Screen"
    case none = "None"
}

public struct GestureMappingProfile: Codable, Sendable {
    public var swipeThreeUp: GestureAction = .missionControl
    public var swipeThreeDown: GestureAction = .appExpose
    public var swipeThreeLeft: GestureAction = .previousSpace
    public var swipeThreeRight: GestureAction = .nextSpace

    public var swipeFourUp: GestureAction = .showDesktop
    public var swipeFourDown: GestureAction = .launchpad
    public var swipeFourLeft: GestureAction = .previousSpace
    public var swipeFourRight: GestureAction = .nextSpace

    public init() {}
}

public final class ActionRouter: @unchecked Sendable {
    public var profile = GestureMappingProfile()
    private let lock = NSLock()

    public init() {}

    public func resolveAction(direction: SwipePayload.Direction, fingers: Int) -> GestureAction {
        lock.lock()
        defer { lock.unlock() }

        if fingers == 3 {
            switch direction {
            case .up: return profile.swipeThreeUp
            case .down: return profile.swipeThreeDown
            case .left: return profile.swipeThreeLeft
            case .right: return profile.swipeThreeRight
            }
        } else if fingers == 4 {
            switch direction {
            case .up: return profile.swipeFourUp
            case .down: return profile.swipeFourDown
            case .left: return profile.swipeFourLeft
            case .right: return profile.swipeFourRight
            }
        }
        return .none
    }
}

