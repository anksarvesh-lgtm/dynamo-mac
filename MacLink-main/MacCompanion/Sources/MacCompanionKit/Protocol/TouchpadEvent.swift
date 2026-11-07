// SPDX-License-Identifier: MIT
import Foundation

/// Canonical event types supported in Touchpad Protocol v1.
public enum TouchpadEventType: String, Codable, Sendable, CaseIterable {
    case pointerMove = "POINTER_MOVE"
    case pointerDown = "POINTER_DOWN"
    case pointerUp = "POINTER_UP"
    case leftClick = "LEFT_CLICK"
    case rightClick = "RIGHT_CLICK"
    case doubleClick = "DOUBLE_CLICK"
    case scroll = "SCROLL"
    case pinch = "PINCH"
    case rotate = "ROTATE"
    case swipe = "SWIPE"
    case keyDown = "KEY_DOWN"
    case keyUp = "KEY_UP"
    case gestureStart = "GESTURE_START"
    case gestureEnd = "GESTURE_END"
    case gestureCancel = "GESTURE_CANCEL"
    case connectionPing = "CONNECTION_PING"
    case connectionPong = "CONNECTION_PONG"
    case deviceStatus = "DEVICE_STATUS"
}

/// Generic payload container for dynamic parsing and serialization.
public struct AnyCodableValue: Codable, Sendable, Equatable {
    public let value: AnySendable

    public init(_ value: AnySendable) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let boolVal = try? container.decode(Bool.self) {
            self.value = .bool(boolVal)
        } else if let intVal = try? container.decode(Int.self) {
            self.value = .int(intVal)
        } else if let doubleVal = try? container.decode(Double.self) {
            self.value = .double(doubleVal)
        } else if let stringVal = try? container.decode(String.self) {
            self.value = .string(stringVal)
        } else if let arrayVal = try? container.decode([AnyCodableValue].self) {
            self.value = .array(arrayVal)
        } else if let dictVal = try? container.decode([String: AnyCodableValue].self) {
            self.value = .dictionary(dictVal)
        } else {
            self.value = .null
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case .bool(let b): try container.encode(b)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .string(let s): try container.encode(s)
        case .array(let a): try container.encode(a)
        case .dictionary(let d): try container.encode(d)
        case .null: try container.encodeNil()
        }
    }
}

public enum AnySendable: Sendable, Equatable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])
    case null
}

extension AnyCodableValue {
    public var asDouble: Double? {
        switch value {
        case .double(let d): return d
        case .int(let i): return Double(i)
        default: return nil
        }
    }

    public var asInt: Int? {
        switch value {
        case .int(let i): return i
        case .double(let d): return Int(d)
        default: return nil
        }
    }

    public var asString: String? {
        if case .string(let s) = value { return s }
        return nil
    }

    public var asBool: Bool? {
        if case .bool(let b) = value { return b }
        return nil
    }
}

/// Unified Touchpad Protocol v1 Envelope.
public struct TouchpadEnvelope: Codable, Sendable, Equatable {
    public let version: Int
    public let sessionId: String
    public let sequence: UInt64
    public let timestamp: UInt64
    public let eventType: TouchpadEventType
    public let payload: [String: AnyCodableValue]

    public init(
        version: Int = 1,
        sessionId: String,
        sequence: UInt64,
        timestamp: UInt64 = UInt64(Date().timeIntervalSince1970 * 1000),
        eventType: TouchpadEventType,
        payload: [String: AnyCodableValue]
    ) {
        self.version = version
        self.sessionId = sessionId
        self.sequence = sequence
        self.timestamp = timestamp
        self.eventType = eventType
        self.payload = payload
    }
}

// MARK: - Typed Payloads

public struct PointerMovePayload: Sendable, Equatable {
    public let deltaX: Double
    public let deltaY: Double

    public init(deltaX: Double, deltaY: Double) {
        self.deltaX = deltaX
        self.deltaY = deltaY
    }
}

public struct PointerButtonPayload: Sendable, Equatable {
    public enum Button: String, Sendable {
        case left
        case right
        case middle
    }
    public let button: Button

    public init(button: Button) {
        self.button = button
    }
}

public struct ScrollPayload: Sendable, Equatable {
    public enum Phase: String, Sendable {
        case began
        case changed
        case ended
        case cancelled
        case none
    }
    public let deltaX: Double
    public let deltaY: Double
    public let isContinuous: Bool
    public let phase: Phase

    public init(deltaX: Double, deltaY: Double, isContinuous: Bool, phase: Phase = .changed) {
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.isContinuous = isContinuous
        self.phase = phase
    }
}

public struct PinchPayload: Sendable, Equatable {
    public let scale: Double
    public let velocity: Double
    public let phase: String

    public init(scale: Double, velocity: Double, phase: String) {
        self.scale = scale
        self.velocity = velocity
        self.phase = phase
    }
}

public struct RotatePayload: Sendable, Equatable {
    public let rotation: Double
    public let velocity: Double
    public let phase: String

    public init(rotation: Double, velocity: Double, phase: String) {
        self.rotation = rotation
        self.velocity = velocity
        self.phase = phase
    }
}

public struct SwipePayload: Sendable, Equatable {
    public enum Direction: String, Sendable {
        case up
        case down
        case left
        case right
    }
    public let direction: Direction
    public let fingers: Int
    public let distance: Double

    public init(direction: Direction, fingers: Int, distance: Double) {
        self.direction = direction
        self.fingers = fingers
        self.distance = distance
    }
}

