//
//  IslandStateModel.swift
//  LiquidDynamo
//
//  Created for Production Dynamic Island Architecture.
//  Provides strict typed state management for central island presentations, utility routes, and carousel navigation.
//

import Foundation

/// Specific destinations available for in-place utility detail expansion.
public enum UtilityRoute: String, Hashable, CaseIterable, Identifiable {
    case clipboard
    case dropper
    case scopa
    case powerload
    case phoneBridge
    case watcher
    case player

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .clipboard: return "Clipboard"
        case .dropper: return "Dropper"
        case .scopa: return "Scopa"
        case .powerload: return "Powerload"
        case .phoneBridge: return "Phone Bridge"
        case .watcher: return "Watcher"
        case .player: return "Now Playing"
        }
    }
}

/// Central island presentation mode with typed routes and unique event identifiers.
public enum IslandMode: Equatable {
    case compact
    case expanded(UtilityRoute)
    case event(UUID)
    case mediaExpanded

    public var isExpanded: Bool {
        switch self {
        case .compact: return false
        case .expanded, .event, .mediaExpanded: return true
        }
    }

    public var route: UtilityRoute? {
        switch self {
        case .expanded(let r): return r
        case .mediaExpanded: return .player
        case .compact, .event: return nil
        }
    }
}

/// Logical carousel slides.
public enum CarouselPage: Int, CaseIterable, Identifiable {
    case productivity = 0
    case systemTools = 1
    case monitoring = 2
    case media = 3

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .productivity: return "Productivity"
        case .systemTools: return "System Tools"
        case .monitoring: return "Monitoring"
        case .media: return "Media Player"
        }
    }
}

