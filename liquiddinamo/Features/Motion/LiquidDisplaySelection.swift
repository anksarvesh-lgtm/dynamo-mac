//
//  LiquidDisplaySelection.swift
//  LiquidDynamo
//
//  LiquidDynamo Core Team
//  Copyright © 2026 Agrigence. All rights reserved.
//

import Foundation

public enum LiquidDisplayMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case builtInOnly
    case all

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .builtInOnly:
            return "Built-in display only"
        case .all:
            return "All displays"
        }
    }
}

public struct LiquidScreenDescriptor: Equatable, Sendable {
    public var isBuiltIn: Bool
    public var hasNotch: Bool
    public var isMenuBarPrimary: Bool

    public init(isBuiltIn: Bool, hasNotch: Bool, isMenuBarPrimary: Bool) {
        self.isBuiltIn = isBuiltIn
        self.hasNotch = hasNotch
        self.isMenuBarPrimary = isMenuBarPrimary
    }
}

public enum LiquidDisplaySelection {
    public static func targetIndices(
        of screens: [LiquidScreenDescriptor],
        mode: LiquidDisplayMode
    ) -> [Int] {
        guard !screens.isEmpty else { return [] }
        switch mode {
        case .all:
            return Array(screens.indices)
        case .builtInOnly:
            if let builtIn = screens.firstIndex(where: { $0.isBuiltIn }) {
                return [builtIn]
            }
            if let primary = screens.firstIndex(where: { $0.isMenuBarPrimary }) {
                return [primary]
            }
            return [0]
        }
    }

    public static func primaryScreenIndex(in screens: [LiquidScreenDescriptor]) -> Int? {
        targetIndices(of: screens, mode: .builtInOnly).first
    }
}
