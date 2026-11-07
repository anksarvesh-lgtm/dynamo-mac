import Foundation

/// Events that flow through the app. Used by automation and diagnostics — never to drive UI directly.
public enum IslandEvent: Sendable, Equatable {
    case activityStarted(id: String, kind: ActivityKind)
    case activityEnded(id: String, kind: ActivityKind)
    case primaryChanged(from: String?, to: String?)
    case batteryLevel(percent: Int, charging: Bool)
    case downloadCompleted(filename: String)
    case timerFinished(label: String)
    case networkChanged(connected: Bool)
    case deviceConnected(name: String)
    case mediaStarted(source: String)
    case activityRejected(reason: String)

    public var name: String {
        switch self {
        case .activityStarted: "activityStarted"
        case .activityEnded: "activityEnded"
        case .primaryChanged: "primaryChanged"
        case .batteryLevel: "batteryLevel"
        case .downloadCompleted: "downloadCompleted"
        case .timerFinished: "timerFinished"
        case .networkChanged: "networkChanged"
        case .deviceConnected: "deviceConnected"
        case .mediaStarted: "mediaStarted"
        case .activityRejected: "activityRejected"
        }
    }
}

/// Minimal main-actor publish/subscribe. Subscribers are isolated: one throwing/misbehaving
/// handler cannot prevent delivery to the others.
@MainActor
public final class EventBus {
    public struct Token: Hashable, Sendable { let raw: UInt64 }
    private var handlers: [UInt64: (IslandEvent) -> Void] = [:]
    private var nextToken: UInt64 = 0
    public private(set) var recent: [(Date, IslandEvent)] = []
    public var recentLimit = 50

    public init() {}

    @discardableResult
    public func subscribe(_ handler: @escaping (IslandEvent) -> Void) -> Token {
        nextToken += 1
        handlers[nextToken] = handler
        return Token(raw: nextToken)
    }

    public func unsubscribe(_ token: Token) { handlers[token.raw] = nil }

    public func publish(_ event: IslandEvent) {
        recent.append((Date(), event))
        if recent.count > recentLimit { recent.removeFirst(recent.count - recentLimit) }
        for key in handlers.keys.sorted() { handlers[key]?(event) }
    }
}
