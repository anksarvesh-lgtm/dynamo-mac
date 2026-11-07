// SPDX-License-Identifier: MIT
import AppKit
import NotchCore
import Observation
import SwiftUI

/// Runs the user's Shortcuts from the notch through the public `shortcuts` command-line tool, so
/// they run in the background without bringing the Shortcuts app forward.
@MainActor
@Observable
public final class ShortcutsFeature: NotchFeature {
    public enum Status: Equatable, Sendable { case loading, ready, unavailable }

    public let id = FeatureID.shortcuts
    public var phase: FeaturePhase = .stopped {
        didSet {
            guard phase != oldValue else { return }
            if phase == .foreground { refresh() }
            if phase == .stopped {
                shortcuts = []
                status = .loading
            }
        }
    }
    public private(set) var shortcuts: [String] = []
    public private(set) var status = Status.loading
    public private(set) var running: Set<String> = []
    /// Shortcuts the user chose not to show in the notch.
    public var hidden: Set<String> {
        didSet { defaults.set(hidden.sorted(), forKey: Self.hiddenKey) }
    }
    /// Raised when a shortcut finishes.
    @ObservationIgnored public var onActivity: ((Activity) -> Void)?

    static let tool = "/usr/bin/shortcuts"
    private static let hiddenKey = "shortcuts.hidden"
    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hidden = Set(defaults.stringArray(forKey: Self.hiddenKey) ?? [])
    }

    public var view: some View { ShortcutsView(shortcuts: self) }

    public var visible: [String] { shortcuts.filter { !hidden.contains($0) } }

    /// Lists the user's shortcuts; called when the tab or its settings come on screen.
    public func refresh() {
        Task {
            let (status, output) = await Subprocess.run(Self.tool, ["list"])
            guard phase != .stopped else { return }  // stopped while listing: stay released
            guard status == 0 else {
                self.status = .unavailable
                return
            }
            shortcuts = Self.parseList(output)
            self.status = .ready
        }
    }

    public func run(_ name: String) {
        guard !running.contains(name) else { return }
        running.insert(name)
        Task {
            let (status, _) = await Subprocess.run(Self.tool, ["run", name])
            running.remove(name)
            let done = status == 0
            onActivity?(
                Activity(
                    feature: .shortcuts,
                    symbol: done ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    title: done ? name : "\(name) failed",
                    duration: .seconds(2)))
        }
    }

    public func openShortcutsApp() {
        let workspace = NSWorkspace.shared
        guard let app = workspace.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") else { return }
        workspace.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    }

    /// One shortcut name per line, sorted the way Finder sorts names.
    static func parseList(_ output: String) -> [String] {
        output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
