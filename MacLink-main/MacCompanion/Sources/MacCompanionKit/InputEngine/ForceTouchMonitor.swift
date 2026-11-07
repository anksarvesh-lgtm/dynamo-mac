// SPDX-License-Identifier: MIT
import AppKit

public enum ForceTouchStage: Int, Sendable {
    case resting = 0
    case normalClick = 1
    case forceClick = 2
}

public protocol ForceTouchDelegate: AnyObject, Sendable {
    func didChangeForceTouchStage(stage: ForceTouchStage, pressure: Float)
}

public final class ForceTouchMonitor: @unchecked Sendable {
    public weak var delegate: ForceTouchDelegate?

    public var isHapticFeedbackEnabled: BooleanLiteralType = true
    private var currentStage: ForceTouchStage = .resting

    public init() {}

    public func processPressureEvent(stage: Int, pressure: Float) {
        let newStage = ForceTouchStage(rawValue: stage) ?? .resting

        if newStage != currentStage {
            currentStage = newStage
            delegate?.didChangeForceTouchStage(stage: newStage, pressure: pressure)

            if isHapticFeedbackEnabled {
                triggerHapticFeedback(for: newStage)
            }
        }
    }

    private func triggerHapticFeedback(for stage: ForceTouchStage) {
        let performer = NSHapticFeedbackManager.defaultPerformer
        switch stage {
        case .normalClick:
            performer.perform(.generic, performanceTime: .default)
        case .forceClick:
            performer.perform(.alignment, performanceTime: .default)
        case .resting:
            break
        }
    }
}

