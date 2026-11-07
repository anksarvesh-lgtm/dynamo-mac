// SPDX-License-Identifier: MIT
import AppKit
import EventKit
import SwiftUI

/// One EventKit store for Calendar and Tasks, created the first time either one needs it, so
/// enabled-but-unopened tabs cost nothing.
@MainActor
public final class EventStore {
    public init() {}

    private(set) lazy var store = EKEventStore()
}

/// Where EventKit access stands for one kind of data.
public enum EventAccess: Equatable, Sendable {
    case notDetermined
    case denied
    case granted

    init(_ type: EKEntityType) {
        switch EKEventStore.authorizationStatus(for: type) {
        case .fullAccess: self = .granted
        case .notDetermined: self = .notDetermined
        default: self = .denied  // denied, restricted, or write-only
        }
    }
}

/// The view for a tab that needs EventKit access it doesn't have yet.
struct EventAccessView: View {
    let access: EventAccess
    let symbol: String
    let what: String
    let settingsPane: String
    let request: () -> Void

    var body: some View {
        if access == .denied {
            FeatureUnavailableView(
                symbol: "lock",
                title: "\(what.capitalized) access is off",
                message: "Turn on ILoveNotch in System Settings › Privacy & Security › \(what.capitalized).",
                action: (
                    label: "Open Privacy Settings",
                    perform: { NSWorkspace.shared.open(.privacySettings(settingsPane)) }
                ))
        } else {
            FeatureUnavailableView(
                symbol: symbol,
                title: "Show your \(what) here",
                message: "ILoveNotch reads your \(what) on this Mac only. Nothing leaves your Mac.",
                action: (label: "Continue", perform: request))  // App Review 5.1.1(iv): not "Allow"
        }
    }
}
