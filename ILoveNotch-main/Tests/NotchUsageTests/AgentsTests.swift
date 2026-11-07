// SPDX-License-Identifier: MIT
import AppKit
import NotchCore
import SwiftUI
import Testing

@testable import NotchUsage

/// A throwaway home and support folder, with Claude Code's and Codex's settings folders in it.
private struct Sandbox {
    let root = FileManager.default.temporaryDirectory.appending(path: "Agents-\(UUID().uuidString)")
    var home: URL { root.appending(path: "home") }
    var hooks: AgentHooks { AgentHooks(home: home, support: root.appending(path: "OpenNotch")) }

    init(tools: [AgentTool] = AgentTool.allCases) throws {
        for tool in tools {
            let folder = home.appending(path: tool.configPath).deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }

    func write(_ settings: [String: Any], for tool: AgentTool) throws {
        let file = hooks.configFile(tool)
        try JSONSerialization.data(withJSONObject: settings).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
    }

    func settings(for tool: AgentTool) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: hooks.configFile(tool))) as? [String: Any])
    }

    /// Runs the installed hook script as an agent would: its input on standard input.
    func runHook(_ tool: String, _ event: String, input: String, app: String? = "com.apple.Terminal") throws {
        let process = Process()
        process.executableURL = hooks.script
        process.arguments = [tool, event]
        process.environment = ["PATH": "/usr/bin:/bin"].merging(app.map { ["__CFBundleIdentifier": $0] } ?? [:]) { $1 }
        let stdin = Pipe()
        process.standardInput = stdin
        try process.run()
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "the hook always exits 0")
    }

    func session(_ id: String) -> AgentSession? {
        let file = hooks.states.appending(path: id)
        guard let contents = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        return AgentSession(id: id, contents: contents, updated: .now)
    }

    /// A session file as the hook script writes it.
    func record(_ id: String, _ state: String, project: String = "/Users/me/Code/nook", process: pid_t) throws {
        try FileManager.default.createDirectory(at: hooks.states, withIntermediateDirectories: true)
        let contents = [state, project, "", "", "\(process)", "", ""].joined(separator: "\n") + "\n"
        try contents.write(to: hooks.states.appending(path: id), atomically: true, encoding: .utf8)
    }
}

/// Someone else's hooks, like the Agent Flow extension's, and a setting that isn't about hooks.
private var theirs: [String: Any] {
    ["model": "opus", "hooks": ["Stop": [["hooks": [["type": "command", "command": "node flow.js", "timeout": 2]]]]]]
}

struct AgentHooksTests {
    @Test func connectingAddsOurHooksBesideTheirsAndDisconnectingPutsTheFileBack() throws {
        let sandbox = try Sandbox()
        let hooks = sandbox.hooks
        try sandbox.write(theirs, for: .claude)
        try hooks.install(.claude)
        try hooks.install(.claude)  // twice: nothing doubles

        #expect(hooks.isInstalled(.claude) && !hooks.isInstalled(.codex))
        let events = try #require(try sandbox.settings(for: .claude)["hooks"] as? [String: [[String: Any]]])
        #expect(Set(events.keys) == ["UserPromptSubmit", "Notification", "PostToolUse", "Stop", "SessionEnd"])
        #expect(events["Stop"]?.count == 2, "theirs first, then ours")
        let notification = try #require(events["Notification"]?.first)
        #expect(notification["matcher"] as? String == "permission_prompt|elicitation_dialog")
        let handler = try #require((notification["hooks"] as? [[String: Any]])?.first)
        #expect(handler["async"] as? Bool == true, "the agent never waits on it")
        #expect((handler["command"] as? String)?.hasSuffix("ilovenotch-agent-hook' claude waiting") == true)
        let attributes = try FileManager.default.attributesOfItem(atPath: hooks.configFile(.claude).path)
        #expect(attributes[.posixPermissions] as? Int == 0o700, "a private settings file stays private")

        try hooks.uninstall(.claude)
        #expect(NSDictionary(dictionary: try sandbox.settings(for: .claude)).isEqual(to: theirs))
        #expect(!FileManager.default.fileExists(atPath: hooks.script.path), "nothing connected: the script goes")
    }

    @Test func aSettingsFileThatIsntJSONIsLeftAlone() throws {
        let sandbox = try Sandbox()
        let file = sandbox.hooks.configFile(.claude)
        try Data("{ \"model\": ".utf8).write(to: file)
        #expect(throws: AgentHooksError.unreadable("~/.claude/settings.json")) { try sandbox.hooks.install(.claude) }
        #expect(try String(contentsOf: file, encoding: .utf8) == "{ \"model\": ")
    }

    @Test func codexGetsAHooksFileThatGoesAwayOnceEmpty() throws {
        let sandbox = try Sandbox()
        try sandbox.hooks.install(.codex)
        let events = try #require(try sandbox.settings(for: .codex)["hooks"] as? [String: Any])
        #expect(events["PermissionRequest"] != nil && events["Notification"] == nil, "Codex asks through its own event")
        try sandbox.hooks.uninstall(.codex)
        #expect(!FileManager.default.fileExists(atPath: sandbox.hooks.configFile(.codex).path))
    }

    @Test func aToolThatIsntOnThisMacCantBeFound() throws {
        let sandbox = try Sandbox(tools: [.codex])
        #expect(!sandbox.hooks.isPresent(.claude) && sandbox.hooks.isPresent(.codex))
    }
}

struct AgentHookScriptTests {
    private let prompt = #"""
        {"session_id":"abc-123","cwd":"/Users/me/Code/nook","hook_event_name":"Notification",
         "message":"Claude needs your permission to use Bash","notification_type":"permission_prompt"}
        """#

    @Test func aSessionGoesFromWorkingToWaitingAndBackToDoneAndAway() throws {
        let sandbox = try Sandbox()
        try sandbox.hooks.install(.claude)
        try sandbox.runHook("claude", "working", input: prompt)
        let working = try #require(sandbox.session("claude-abc-123"))
        #expect(working.state == .working && working.project == "nook" && working.app == "com.apple.Terminal")

        try sandbox.runHook("claude", "waiting", input: prompt)
        #expect(sandbox.session("claude-abc-123")?.state == .waiting)
        #expect(sandbox.session("claude-abc-123")?.detail == "Claude needs your permission to use Bash")
        try sandbox.runHook("claude", "resumed", input: prompt)
        #expect(sandbox.session("claude-abc-123")?.state == .working, "answering the prompt resumes it")

        try sandbox.runHook("claude", "done", input: prompt)
        try sandbox.runHook("claude", "resumed", input: prompt)
        #expect(sandbox.session("claude-abc-123")?.state == .done, "a tool call only resumes a waiting session")
        try sandbox.runHook("claude", "ended", input: prompt)
        #expect(sandbox.session("claude-abc-123") == nil)
    }

    @Test func withoutTheSessionFolderTheHookDoesNothing() throws {
        let sandbox = try Sandbox()
        try sandbox.hooks.install(.claude)
        try FileManager.default.removeItem(at: sandbox.hooks.states)
        try sandbox.runHook("claude", "waiting", input: prompt)
        #expect(!FileManager.default.fileExists(atPath: sandbox.hooks.states.path))
        try sandbox.runHook("claude", "waiting", input: "not json at all")
    }
}

@MainActor
struct AgentsFeatureTests {
    private let defaults = UserDefaults(suiteName: "Agents.\(UUID().uuidString)")!

    @Test func aWaitingAgentRestsInTheNotchAndOneThatFinishesIsAnnounced() throws {
        let sandbox = try Sandbox()
        try sandbox.hooks.install(.claude)
        let agents = AgentsFeature(hooks: sandbox.hooks, defaults: defaults)
        var ongoing: [Activity?] = []
        var activities: [Activity] = []
        agents.onOngoing = { ongoing.append($0) }
        agents.onActivity = { activities.append($0) }
        agents.phase = .background
        #expect(agents.connected == [.claude] && agents.isWatching)

        try sandbox.record("claude-s1", "waiting", process: getpid())
        agents.reload(announcing: true)
        #expect(ongoing.last??.title == "nook" && ongoing.last??.symbol == "hand.raised.fill")
        try sandbox.record("claude-s2", "waiting", project: "/tmp/other", process: getpid())
        agents.reload(announcing: true)
        #expect(ongoing.last??.title == "2 waiting")

        try sandbox.record("claude-s1", "done", process: getpid())
        try sandbox.record("claude-s2", "working", project: "/tmp/other", process: getpid())
        agents.reload(announcing: true)
        #expect(activities.map(\.title) == ["nook"], "it finished while its app wasn't in front")
        #expect(ongoing.last == .some(nil), "nobody's waiting")

        agents.phase = .stopped
        #expect(!agents.isWatching && agents.sessions.isEmpty)
    }

    @Test func aSessionWhoseAgentQuitIsDropped() throws {
        let sandbox = try Sandbox()
        try sandbox.hooks.install(.claude)
        let ended = Process()
        ended.executableURL = URL(filePath: "/usr/bin/true")
        try ended.run()
        ended.waitUntilExit()
        try sandbox.record("claude-gone", "waiting", process: ended.processIdentifier)
        let agents = AgentsFeature(hooks: sandbox.hooks, defaults: defaults)
        agents.phase = .background
        #expect(agents.sessions.isEmpty && sandbox.session("claude-gone") == nil)
    }

    @Test func theFolderWatchSeesTheHooksWrites() async throws {
        let sandbox = try Sandbox()
        try sandbox.hooks.install(.codex)
        let agents = AgentsFeature(hooks: sandbox.hooks, defaults: defaults)
        agents.phase = .background
        let input = #"{"session_id":"t-9","cwd":"/work/api","tool_name":"exec_command"}"#
        try sandbox.runHook("codex", "waiting", input: input, app: nil)
        #expect(await eventually { agents.sessions.first?.state == .waiting })
        #expect(agents.sessions.first?.detail == "Wants to use exec_command" && agents.sessions.first?.tool == .codex)
        agents.phase = .stopped
    }

    @Test func theTabOffersToConnectThenListsSessions() throws {
        let sandbox = try Sandbox()
        let agents = AgentsFeature(hooks: sandbox.hooks, defaults: defaults)
        agents.phase = .foreground
        try render(agents.view, name: "agents-setup")
        agents.connect(.claude)
        try sandbox.record("claude-a", "waiting", project: "/Users/me/Code/nook", process: getpid())
        try sandbox.record("claude-b", "working", project: "/Users/me/Code/api", process: getpid())
        try sandbox.record("codex-c", "done", project: "/Users/me/Code/site", process: getpid())
        agents.reload(announcing: false)
        #expect(agents.sessions.count == 3)
        try render(agents.view, name: "agents")
        agents.phase = .stopped
    }

    /// The tab as the notch shows it, at the default size and the smallest; with SNAPSHOT_DIR set,
    /// also PNGs there.
    private func render(_ view: some View, name: String) throws {
        try render(view, name: name, size: CGSize(width: 396, height: 192))
        try render(view, name: name + "-smallest", size: CGSize(width: 350, height: 102))
    }

    private func render(_ view: some View, name: String, size: CGSize) throws {
        let framed = view.frame(width: size.width, height: size.height).padding(16).background(.black)
            .foregroundStyle(.white).environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: framed)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: CGSize(width: size.width + 32, height: size.height + 32)),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        #expect(bitmap.pixelsWide > 0)
        if let directory = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try bitmap.representation(using: .png, properties: [:])?.write(
                to: URL(filePath: directory).appending(path: "\(name).png"))
        }
    }

    @Test func sessionFilesAreReadLineByLine() throws {
        let session = try #require(
            AgentSession(
                id: "codex-7", contents: "done\n/Users/me/site\n\nApple_Terminal\n42\n\n\n", updated: .now))
        #expect(session.tool == .codex && session.state == .done && session.project == "site")
        #expect(session.app == "com.apple.Terminal", "a terminal that doesn't pass its bundle ID on")
        #expect(AgentSession(id: "cursor-1", contents: "done\n\n\n\n1\n", updated: .now) == nil, "not ours")
        #expect(AgentSession(id: "claude-1", contents: "sleeping\n\n\n\n1\n", updated: .now) == nil)
    }
}
