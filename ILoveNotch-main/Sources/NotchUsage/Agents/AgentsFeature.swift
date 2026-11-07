// SPDX-License-Identifier: MIT
import AppKit
import NotchCore
import NotchFeatures
import Observation
import SwiftUI

/// One agent session, as its hook last described it.
public struct AgentSession: Identifiable, Hashable, Sendable {
    public enum State: String, Sendable {
        case working, waiting, done
    }

    /// "<tool>-<session id>", its file's name.
    public var id: String
    public var tool: AgentTool
    public var state: State
    /// The folder it works in, by name.
    public var project: String
    /// The app it runs in: a Terminal, iTerm, VS Code, and so on.
    public var app: String?
    /// The agent's process, to tell a session that ended without saying so.
    var process: pid_t?
    /// What it's waiting for, in the tool's words.
    public var detail: String?
    public var updated: Date

    /// Reads a session file: one field per line, as the hook script writes it.
    init?(id: String, contents: String, updated: Date) {
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard lines.count >= 5, let state = State(rawValue: lines[0]),
            let tool = AgentTool(rawValue: String(id.prefix { $0 != "-" }))
        else { return nil }
        func text(_ index: Int) -> String? {
            lines.indices.contains(index) && !lines[index].isEmpty ? lines[index] : nil
        }
        self.id = id
        self.tool = tool
        self.state = state
        project = text(1).map { URL(filePath: $0).lastPathComponent } ?? tool.name
        app = text(2) ?? text(3).flatMap { Self.terminals[$0] }
        process = text(4).flatMap { pid_t($0) }
        detail = text(5) ?? text(6).map { "Wants to use \($0)" }
        self.updated = updated
    }

    init(id: String, tool: AgentTool, state: State, project: String, app: String? = nil, updated: Date) {
        self.id = id
        self.tool = tool
        self.state = state
        self.project = project
        self.app = app
        self.updated = updated
    }

    /// `TERM_PROGRAM` to bundle ID, for terminals that don't pass their bundle ID on.
    private static let terminals = [
        "Apple_Terminal": "com.apple.Terminal", "iTerm.app": "com.googlecode.iterm2", "vscode": "com.microsoft.VSCode",
        "WarpTerminal": "dev.warp.Warp-Stable", "ghostty": "com.mitchellh.ghostty", "WezTerm": "com.github.wez.wezterm",
    ]

    /// A session whose agent quit, or that hasn't been heard from in a day, is over.
    func isOver(at now: Date) -> Bool {
        if now.timeIntervalSince(updated) > 24 * 3600 { return true }
        guard let process, process > 1 else { return false }
        return kill(process, 0) != 0 && errno == ESRCH
    }
}

/// Agent status: what Claude Code and Codex are doing in their terminals. Their own hooks (added
/// only when the user connects a tool, see `AgentHooks`) write a small file per session; this
/// watches that folder for changes, so nothing runs between events. While an agent waits for
/// approval, the closed notch says so until it's answered; when one finishes while its app is in
/// the background, the notch says that too. The GitHub build only: hooks don't fit the App Sandbox.
@MainActor
@Observable
public final class AgentsFeature: NotchFeature {
    public let id = FeatureID.agents
    public var phase: FeaturePhase = .stopped {
        didSet { if phase != oldValue { update() } }
    }
    /// Waiting ones first, then newest first.
    public private(set) var sessions: [AgentSession] = []
    /// Tools with the notch's hooks in their settings.
    public private(set) var connected: Set<AgentTool> = []
    /// Why the last connect or disconnect failed.
    public private(set) var failure: String?
    /// Per-feature setting: a live activity when an agent finishes while its app is in the background.
    public var announcesDone: Bool {
        didSet { defaults.set(announcesDone, forKey: Self.announceKey) }
    }
    /// Raised when an agent finishes.
    @ObservationIgnored public var onActivity: ((Activity) -> Void)?
    /// Agents waiting for approval, for the closed notch; nil when none is.
    @ObservationIgnored public var onOngoing: ((Activity?) -> Void)?

    let hooks: AgentHooks
    private static let announceKey = "agents.announcesDone"
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var shownWaiting: Activity?

    public convenience init(defaults: UserDefaults = .standard) {
        self.init(hooks: AgentHooks(), defaults: defaults)
    }

    init(hooks: AgentHooks, defaults: UserDefaults) {
        self.hooks = hooks
        self.defaults = defaults
        announcesDone = defaults.object(forKey: Self.announceKey) as? Bool ?? true
    }

    public var view: some View { AgentsView(agents: self) }

    /// Tools that are on this Mac, which can be connected.
    public var available: [AgentTool] { AgentTool.allCases.filter { hooks.isPresent($0) || connected.contains($0) } }

    /// Whether the session folder is being watched.
    var isWatching: Bool { watcher != nil }

    public func connect(_ tool: AgentTool) { change { try hooks.install(tool) } }

    public func disconnect(_ tool: AgentTool) { change { try hooks.uninstall(tool) } }

    /// Looks at the tools' settings again, which the user may have edited by hand.
    public func refreshConnected() {
        connected = Set(AgentTool.allCases.filter(hooks.isInstalled))
        if !connected.isEmpty { hooks.refreshScript() }
    }

    /// Brings the app the session runs in forward. Through Launch Services, like opening Calendar
    /// from its tab: the notch's app is never active, and macOS ignores activation requests from
    /// apps that aren't.
    public func open(_ session: AgentSession) {
        guard let app = session.app, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app)
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Forgets a session, for one whose agent ended without saying so.
    public func clear(_ session: AgentSession) {
        try? FileManager.default.removeItem(at: hooks.states.appending(path: session.id))
        reload(announcing: false)
    }

    private func change(_ action: () throws -> Void) {
        do {
            try action()
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
        update()
    }

    /// Watches the session folder while a tool is connected and the notch runs; stopped, it lets
    /// go of everything.
    private func update() {
        refreshConnected()
        guard phase != .stopped, !connected.isEmpty else {
            watcher?.cancel()
            watcher = nil
            sessions = []
            showWaiting(nil)
            return
        }
        if watcher == nil { watch() }
        reload(announcing: false)
    }

    /// A new, renamed, or removed session file changes the folder; the hook script renames each
    /// file into place, so every update is one of those.
    private func watch() {
        try? FileManager.default.createDirectory(at: hooks.states, withIntermediateDirectories: true)
        let folder = Darwin.open(hooks.states.path, O_EVTONLY)
        guard folder >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: folder, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.reload(announcing: true) }
        }
        source.setCancelHandler { close(folder) }
        source.resume()
        watcher = source
    }

    /// Reads every session again, drops the ones that are over, and tells the notch what changed.
    func reload(announcing: Bool, now: Date = .now) {
        let fileManager = FileManager.default
        let files =
            (try? fileManager.contentsOfDirectory(
                at: hooks.states, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        var found: [AgentSession] = []
        for file in files where !file.lastPathComponent.hasPrefix(".") {
            guard let contents = try? String(contentsOf: file, encoding: .utf8),
                let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                let session = AgentSession(id: file.lastPathComponent, contents: contents, updated: modified)
            else { continue }
            if session.isOver(at: now) {
                try? fileManager.removeItem(at: file)
            } else {
                found.append(session)
            }
        }
        // Waiting ones first, since those need the user; then the latest news.
        found.sort { ($0.state == .waiting ? 1 : 0, $0.updated) > ($1.state == .waiting ? 1 : 0, $1.updated) }
        let before = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0.state) })
        sessions = found
        if announcing, announcesDone {
            // Only a session seen working finishes; one found already done is old news.
            let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            for session in found where session.state == .done {
                guard let previous = before[session.id], previous != .done, session.app != front else { continue }
                onActivity?(
                    Activity(
                        feature: .agents, symbol: "checkmark.circle.fill", title: session.project,
                        duration: .seconds(3)))
            }
        }
        showWaiting(Self.waiting(in: found))
    }

    /// The closed notch's reminder that agents are waiting for approval: the project when it's one.
    static func waiting(in sessions: [AgentSession]) -> Activity? {
        let waiting = sessions.filter { $0.state == .waiting }
        guard let first = waiting.first else { return nil }
        let title = waiting.count == 1 ? first.project : "\(waiting.count) waiting"
        return Activity(feature: .agents, symbol: "hand.raised.fill", title: title, duration: .zero)
    }

    private func showWaiting(_ activity: Activity?) {
        guard activity != shownWaiting else { return }
        shownWaiting = activity
        onOngoing?(activity)
    }
}
