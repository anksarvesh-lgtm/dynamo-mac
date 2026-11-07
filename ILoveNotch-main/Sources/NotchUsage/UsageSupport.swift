// SPDX-License-Identifier: MIT
import Foundation
import NotchCore
import os

// OpenNotch's stand-ins for the parts of OpenUsage's app that its providers call into: logging, the
// resource bundle, and the time format. OpenUsage's versions read its own settings and write a log
// file; these keep the same shapes so the vendored providers compile unchanged.

/// OpenUsage's log tags.
enum LogTag: String, Sendable {
    case refresh
    case cache
    case http
    case auth
    case keychain
    case menubar
    case updates
    case config
    case statusItem = "statusitem"
    case localAPI = "localapi"
    case subprocess
    case lifecycle
    case notifications

    static func plugin(_ id: String) -> String { "plugin:\(id)" }
    static func auth(_ id: String) -> String { "auth:\(id)" }
}

/// OpenUsage's logging calls, sent to OpenNotch's unified log (category "usage") instead of a file.
/// Messages go through OpenUsage's redaction first, since they can mention accounts and endpoints.
enum AppLog {
    private static let logger = Logger(subsystem: Log.subsystem, category: "usage")

    static func error(_ tag: String, _ message: @autoclosure () -> String) { emit(.error, tag, message()) }
    static func warn(_ tag: String, _ message: @autoclosure () -> String) { emit(.default, tag, message()) }
    static func info(_ tag: String, _ message: @autoclosure () -> String) { emit(.info, tag, message()) }
    static func debug(_ tag: String, _ message: @autoclosure () -> String) { emit(.debug, tag, message()) }

    static func error(_ tag: LogTag, _ message: @autoclosure () -> String) { emit(.error, tag.rawValue, message()) }
    static func warn(_ tag: LogTag, _ message: @autoclosure () -> String) { emit(.default, tag.rawValue, message()) }
    static func info(_ tag: LogTag, _ message: @autoclosure () -> String) { emit(.info, tag.rawValue, message()) }
    static func debug(_ tag: LogTag, _ message: @autoclosure () -> String) { emit(.debug, tag.rawValue, message()) }

    private static func emit(_ type: OSLogType, _ tag: String, _ message: String) {
        let text = LogRedaction.redactLogMessage(message)
        logger.log(level: type, "[\(tag, privacy: .public)] \(text, privacy: .public)")
    }
}

extension Bundle {
    /// NotchUsage's resources (the pricing snapshots). The app's Resources come first: in a packaged
    /// app, SwiftPM's `Bundle.module` can fail to find its bundle and stop the app (OpenUsage's
    /// `ResourceBundle` explains the same trap).
    static let openUsageResources: Bundle = {
        let name = "OpenNotchKit_NotchUsage.bundle"
        for case let base? in [Bundle.main.resourceURL, Bundle.main.bundleURL] {
            if let bundle = Bundle(url: base.appending(path: name)),
                bundle.url(forResource: "pricing_supplement", withExtension: "json") != nil
            {
                return bundle
            }
        }
        return .module
    }()
}

/// OpenUsage lets people pick 12- or 24-hour times; OpenNotch follows the system's choice.
enum TimeFormatSetting: Sendable {
    case system

    static var current: TimeFormatSetting { .system }

    func shortTime(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
}
