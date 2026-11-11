// SPDX-License-Identifier: MIT
import Foundation
import IOKit.pwr_mgt

// MARK: - Keep Awake Mode

public enum KeepAwakeMode: String, CaseIterable, Codable, Identifiable {
    case system = "system"
    case displayAndSystem = "displayAndSystem"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system:
            return "Keep System Awake"
        case .displayAndSystem:
            return "Keep Display & System Awake"
        }
    }

    public var shortTitle: String {
        switch self {
        case .system:
            return "System Only"
        case .displayAndSystem:
            return "System + Display"
        }
    }

    public var subtitle: String {
        switch self {
        case .system:
            return "Display may turn off to save energy; background tasks continue running."
        case .displayAndSystem:
            return "Both the screen and the system remain awake without dimming."
        }
    }

    public var iconName: String {
        switch self {
        case .system:
            return "cpu"
        case .displayAndSystem:
            return "display"
        }
    }

    public var assertionType: CFString {
        switch self {
        case .system:
            return kIOPMAssertionTypePreventUserIdleSystemSleep as CFString
        case .displayAndSystem:
            return kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString
        }
    }
}

// MARK: - Keep Awake Preset

public enum KeepAwakePreset: String, CaseIterable, Codable, Identifiable {
    case m15 = "15m"
    case m30 = "30m"
    case h1 = "1h"
    case h2 = "2h"
    case h4 = "4h"
    case h8 = "8h"
    case indefinite = "indefinite"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .m15: return "15m"
        case .m30: return "30m"
        case .h1: return "1h"
        case .h2: return "2h"
        case .h4: return "4h"
        case .h8: return "8h"
        case .indefinite: return "Indefinite"
        }
    }

    public var fullTitle: String {
        switch self {
        case .m15: return "15 Minutes"
        case .m30: return "30 Minutes"
        case .h1: return "1 Hour"
        case .h2: return "2 Hours"
        case .h4: return "4 Hours"
        case .h8: return "8 Hours"
        case .indefinite: return "Indefinitely"
        }
    }

    public var durationSeconds: TimeInterval? {
        switch self {
        case .m15: return 15 * 60
        case .m30: return 30 * 60
        case .h1: return 60 * 60
        case .h2: return 2 * 60 * 60
        case .h4: return 4 * 60 * 60
        case .h8: return 8 * 60 * 60
        case .indefinite: return nil
        }
    }
}

// MARK: - Keep Awake Duration Specifier

public enum KeepAwakeDuration: Equatable {
    case preset(KeepAwakePreset)
    case custom(TimeInterval)
    case indefinite

    public var isIndefinite: Bool {
        switch self {
        case .indefinite:
            return true
        case .preset(let p):
            return p == .indefinite
        case .custom:
            return false
        }
    }

    public var durationSeconds: TimeInterval? {
        switch self {
        case .indefinite:
            return nil
        case .preset(let preset):
            return preset.durationSeconds
        case .custom(let interval):
            return interval
        }
    }

    public static func validate(hours: Int, minutes: Int) -> Result<TimeInterval, KeepAwakeValidationError> {
        if hours < 0 || minutes < 0 {
            return .failure(.negativeDuration)
        }
        let totalSeconds = TimeInterval(hours * 3600 + minutes * 60)
        if totalSeconds < 60 {
            return .failure(.tooShort)
        }
        if totalSeconds > 24 * 3600 {
            return .failure(.tooLong)
        }
        return .success(totalSeconds)
    }
}

// MARK: - Validation Errors

public enum KeepAwakeValidationError: LocalizedError, Equatable {
    case negativeDuration
    case tooShort
    case tooLong

    public var errorDescription: String? {
        switch self {
        case .negativeDuration:
            return "Duration cannot be negative."
        case .tooShort:
            return "Minimum Keep Awake duration is 1 minute."
        case .tooLong:
            return "Maximum Keep Awake duration is 24 hours."
        }
    }
}
