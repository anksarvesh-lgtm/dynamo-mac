import Foundation

/// Every action carries a safety level. Island only ever executes `.safe` actions automatically;
/// `.confirm` needs an explicit user gesture; `.forbidden` is never executed (by users, rules, or AI).
public enum SafetyLevel: Int, Comparable, Sendable, Codable {
    case safe = 0, confirm = 1, forbidden = 2
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// Where a request originated. AI and automation are held to stricter rules than direct user input.
public enum ActionOrigin: String, Sendable, Codable { case user, automation, ai }

public enum PermissionPolicy {
    public static func isAllowed(_ level: SafetyLevel, origin: ActionOrigin, userConfirmed: Bool) -> Bool {
        switch level {
        case .safe: true
        case .confirm: origin == .user && userConfirmed
        case .forbidden: false
        }
    }
}
