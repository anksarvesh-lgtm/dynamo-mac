import Foundation

public enum IslandMode: String, Equatable, Sendable {
    /// No activity: the Island hides inside the notch.
    case idle
    /// Glanceable state hugging the notch.
    case compact
    /// Large interactive surface.
    case expanded
    /// Keyboard-driven search surface.
    case search
}

public enum ExpansionReason: String, Equatable, Sendable { case none, hover, click, transient, command }

public enum IslandInput: Equatable, Sendable {
    case hoverBegan, hoverEnded
    case click, clickOutside, escape
    case toggleSearch
    case activityAvailabilityChanged(hasActivity: Bool)
    case expand, collapse
    case presentTransient, transientEnded
    case autoCollapse
}

/// Pure state machine for compact ⇄ expanded ⇄ search. Timing (hover intent, collapse delays)
/// lives in the view model; this type only decides *what* the mode should be.
public struct IslandPresentation: Equatable, Sendable {
    public private(set) var mode: IslandMode = .idle
    public private(set) var reason: ExpansionReason = .none
    public private(set) var hovering = false
    public private(set) var hasActivity = false
    public var hoverExpansionEnabled = true

    public init(hoverExpansionEnabled: Bool = true) {
        self.hoverExpansionEnabled = hoverExpansionEnabled
    }

    public var restingMode: IslandMode { hasActivity ? .compact : .idle }
    public var isExpanded: Bool { mode == .expanded || mode == .search }

    @discardableResult
    public mutating func handle(_ input: IslandInput) -> IslandMode {
        switch input {
        case .hoverBegan:
            hovering = true
            if hoverExpansionEnabled, !isExpanded { expand(.hover) }
        case .hoverEnded:
            hovering = false
            if mode == .expanded, reason != .command { rest() }
        case .click:
            if !isExpanded { expand(.click) }
        case .clickOutside:
            // A system-presented card (e.g. AirPods connected) holds for its full duration.
            if isExpanded, reason != .transient { rest() }
        case .escape:
            if isExpanded { rest() }
        case .toggleSearch:
            if mode == .search { rest() } else { mode = .search; reason = .command }
        case .activityAvailabilityChanged(let has):
            hasActivity = has
            if !isExpanded { mode = restingMode }
        case .expand:
            if mode != .expanded { expand(.command) }
        case .collapse:
            if isExpanded { rest() }
        case .presentTransient:
            if !isExpanded { expand(.transient) }
        case .transientEnded:
            if mode == .expanded, reason == .transient, !hovering { rest() }
        case .autoCollapse:
            if mode == .expanded, !hovering { rest() }
        }
        return mode
    }

    private mutating func expand(_ r: ExpansionReason) {
        mode = .expanded
        reason = r
    }

    private mutating func rest() {
        mode = restingMode
        reason = .none
    }
}
