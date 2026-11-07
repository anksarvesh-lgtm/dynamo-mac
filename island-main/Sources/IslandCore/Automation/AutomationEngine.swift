import Foundation

/// WHEN (trigger) IF (conditions) THEN (actions). Rules are data; actions are a closed set of safe,
/// typed effects — automation can never run arbitrary commands or change system settings.
public struct AutomationRule: Codable, Identifiable, Equatable, Sendable {
    public enum Trigger: Codable, Equatable, Sendable {
        case batteryBelow(percent: Int)
        case downloadCompleted
        case timerFinished
        case mediaStarted
        case networkChanged(connected: Bool)
        case deviceConnected
    }

    public enum Condition: Codable, Equatable, Sendable {
        case hourBetween(start: Int, end: Int)
        case activityActive(ActivityKind)
        case activityInactive(ActivityKind)
    }

    public enum Action: Codable, Equatable, Sendable {
        case presentIsland(seconds: Double)
        case showEvent(symbol: String, title: String)
        case playSound(name: String)
    }

    public var id: UUID
    public var name: String
    public var enabled: Bool
    public var trigger: Trigger
    public var conditions: [Condition]
    public var actions: [Action]

    public init(id: UUID = UUID(), name: String, enabled: Bool = true, trigger: Trigger, conditions: [Condition] = [], actions: [Action]) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.trigger = trigger
        self.conditions = conditions
        self.actions = actions
    }

    public static let defaults: [AutomationRule] = [
        AutomationRule(name: "Battery below 20% → show Island", trigger: .batteryBelow(percent: 20), actions: [.presentIsland(seconds: 4)]),
        AutomationRule(name: "Download completed → show Island", trigger: .downloadCompleted, actions: [.presentIsland(seconds: 3)]),
        AutomationRule(name: "AirPods / headphones connected → show Island", trigger: .deviceConnected, actions: [.presentIsland(seconds: 4.5)]),
        AutomationRule(name: "Music started → show media", trigger: .mediaStarted, enabled: false, actions: [.presentIsland(seconds: 3)]),
    ]

    init(name: String, trigger: Trigger, enabled: Bool = true, actions: [Action]) {
        self.init(id: UUID(), name: name, enabled: enabled, trigger: trigger, conditions: [], actions: actions)
    }
}

public struct AutomationContext: Sendable {
    public var now: Date
    public var activeKinds: Set<ActivityKind>
    public var calendar: Calendar
    public init(now: Date = Date(), activeKinds: Set<ActivityKind>, calendar: Calendar = .current) {
        self.now = now
        self.activeKinds = activeKinds
        self.calendar = calendar
    }
}

public enum AutomationEngine {
    /// Pure evaluation: which actions should run for this event.
    public static func evaluate(_ rules: [AutomationRule], event: IslandEvent, context: AutomationContext,
                                state: inout [UUID: Bool]) -> [AutomationRule.Action] {
        var actions: [AutomationRule.Action] = []
        for rule in rules where rule.enabled {
            guard matches(rule, event: event, state: &state), rule.conditions.allSatisfy({ holds($0, context) }) else { continue }
            actions.append(contentsOf: rule.actions)
        }
        return actions
    }

    static func matches(_ rule: AutomationRule, event: IslandEvent, state: inout [UUID: Bool]) -> Bool {
        switch (rule.trigger, event) {
        case (.batteryBelow(let threshold), .batteryLevel(let pct, let charging)):
            // Edge-triggered: fire once when crossing below, re-arm when back above or charging.
            let below = pct < threshold && !charging
            let wasBelow = state[rule.id] ?? false
            state[rule.id] = below
            return below && !wasBelow
        case (.downloadCompleted, .downloadCompleted), (.timerFinished, .timerFinished), (.mediaStarted, .mediaStarted),
             (.deviceConnected, .deviceConnected):
            return true
        case (.networkChanged(let want), .networkChanged(let connected)):
            return want == connected
        default:
            return false
        }
    }

    static func holds(_ c: AutomationRule.Condition, _ ctx: AutomationContext) -> Bool {
        switch c {
        case .hourBetween(let s, let e):
            let h = ctx.calendar.component(.hour, from: ctx.now)
            return s <= e ? (h >= s && h < e) : (h >= s || h < e)
        case .activityActive(let k): return ctx.activeKinds.contains(k)
        case .activityInactive(let k): return !ctx.activeKinds.contains(k)
        }
    }
}

/// Persists rules (JSON in UserDefaults).
public enum AutomationStore {
    static let key = "island.automation.v1"
    public static func load(_ d: UserDefaults = .standard) -> [AutomationRule] {
        guard let data = d.data(forKey: key), let rules = try? JSONDecoder().decode([AutomationRule].self, from: data) else { return AutomationRule.defaults }
        return rules
    }
    public static func save(_ rules: [AutomationRule], _ d: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(rules) { d.set(data, forKey: key) }
    }
}
