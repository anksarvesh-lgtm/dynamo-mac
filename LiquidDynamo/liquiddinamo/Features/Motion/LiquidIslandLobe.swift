//
//  LiquidIslandLobe.swift
//  LiquidDynamo
//
//  Data model and parameters for the Liquid Island SDF Lobe System.
//

import Foundation
import SwiftUI

/// Single SDF geometric lobe representing a fluid region (Root, Body, Wings, Droplet, Satellites).
public struct LiquidIslandLobe: Identifiable, Sendable {
    public let id: Int
    public var name: String
    public var centerX: CGFloat
    public var centerY: CGFloat
    public var halfWidth: CGFloat
    public var halfHeight: CGFloat
    public var cornerRadius: CGFloat
    public var isActive: Bool
    public var weight: CGFloat

    public init(
        id: Int,
        name: String,
        centerX: CGFloat,
        centerY: CGFloat,
        halfWidth: CGFloat,
        halfHeight: CGFloat,
        cornerRadius: CGFloat,
        isActive: Bool = true,
        weight: CGFloat = 1.0
    ) {
        self.id = id
        self.name = name
        self.centerX = centerX
        self.centerY = centerY
        self.halfWidth = halfWidth
        self.halfHeight = halfHeight
        self.cornerRadius = cornerRadius
        self.isActive = isActive
        self.weight = weight
    }

    /// Converts lobe data into 8 floats for the Metal buffer
    public func toFloat8() -> [Float] {
        return [
            Float(centerX),
            Float(centerY),
            Float(halfWidth),
            Float(halfHeight),
            Float(cornerRadius),
            isActive ? 1.0 : 0.0,
            Float(weight),
            0.0 // Reserved alignment
        ]
    }
}

/// Parameters controlling the 3D optical lighting and fluid fusion of the Liquid Island Engine.
public struct LiquidLightingConfig: Sendable, Equatable {
    public var lightDirX: Float = -0.55
    public var lightDirY: Float = -0.75
    public var lightDirZ: Float = 1.25
    public var tightPower: Float = 32.0
    public var tightSpecIntensity: Float = 0.70
    public var broadSpecIntensity: Float = 0.28
    public var fresnelIntensity: Float = 0.55
    public var innerDepthIntensity: Float = 0.35
    public var kSmoothing: CGFloat = 16.0

    public init() {}
}

/// Pre-configured tint palettes adhering to Master Spec (Agrigence Emerald + Severity)
public enum LiquidIslandTintPreset: String, CaseIterable, Identifiable {
    case agrigenceEmerald = "Emerald"
    case oceanicCyan = "Cyan"
    case amberWarning = "Amber"
    case crimsonCritical = "Crimson"
    case nebulaPurple = "Purple"

    public var id: String { rawValue }

    public var color: Color {
        switch self {
        case .agrigenceEmerald:
            return Color(red: 0.06, green: 0.75, blue: 0.52)
        case .oceanicCyan:
            return Color(red: 0.05, green: 0.70, blue: 0.88)
        case .amberWarning:
            return Color(red: 0.96, green: 0.62, blue: 0.07)
        case .crimsonCritical:
            return Color(red: 0.93, green: 0.27, blue: 0.27)
        case .nebulaPurple:
            return Color(red: 0.64, green: 0.38, blue: 0.98)
        }
    }

    public var float4: (Float, Float, Float, Float) {
        switch self {
        case .agrigenceEmerald: return (0.06, 0.75, 0.52, 1.0)
        case .oceanicCyan:      return (0.05, 0.70, 0.88, 1.0)
        case .amberWarning:     return (0.96, 0.62, 0.07, 1.0)
        case .crimsonCritical:  return (0.93, 0.27, 0.27, 1.0)
        case .nebulaPurple:     return (0.64, 0.38, 0.98, 1.0)
        }
    }
}
