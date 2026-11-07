// SPDX-License-Identifier: MIT
import Foundation
import NotchFeatures

/// A coding agent whose hooks can report to the notch.
public enum AgentTool: String, CaseIterable, Identifiable, Sendable {
    case claude, codex

    public var id: Self { self }

    public var name: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }

    /// For the closed notch, where there's little room.
    public var shortName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    /// Its hooks file, relative to the home folder.
    var configPath: String {
        switch self {
        case .claude: ".claude/settings.json"
        case .codex: ".codex/hooks.json"
        }
    }

    /// The tool's hook events, what each one means for the notch, and which of an event's cases
    /// count. Claude Code tells hooks it needs approval through a notification, sent once a prompt
    /// has waited a few seconds; Codex has an event for it. Claude's "waiting for your input" after
    /// every idle minute isn't asking for anything, so it's left out.
    var events: [(event: String, matcher: String?, state: String)] {
        let waiting: (String, String?, String) =
            switch self {
            case .claude: ("Notification", "permission_prompt|elicitation_dialog", "waiting")
            case .codex: ("PermissionRequest", nil, "waiting")
            }
        return [
            ("UserPromptSubmit", nil, "working"), waiting, ("PostToolUse", nil, "resumed"), ("Stop", nil, "done"),
            ("SessionEnd", nil, "ended"),
        ]
    }
}

/// What went wrong changing a tool's settings. Nothing is written when any of these happen.
public enum AgentHooksError: LocalizedError, Equatable {
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let path): "\(path) isn't a JSON object ILoveNotch can read, so it wasn't changed."
        }
    }
}

/// Adds and removes the notch's hooks in Claude Code's and Codex's own settings: opt-in per tool,
/// next to whatever hooks are already there, and removing takes out exactly what adding put in.
/// The hooks run a small script that writes one file per session into `states`, which
/// `AgentsFeature` watches.
public struct AgentHooks: Sendable {
    let home: URL
    /// The hook script, named so ILoveNotch can always tell its hooks from anyone else's.
    let script: URL
    /// Where the script writes each session's state.
    let states: URL
    /// A copy of each settings file from just before ILoveNotch last changed it.
    let backups: URL

    static let scriptName = "ilovenotch-agent-hook"

    public init() {
        self.init(
            home: FileManager.default.homeDirectoryForCurrentUser,
            support: AppSupport.file(Self.scriptName).deletingLastPathComponent())
    }

    init(home: URL, support: URL) {
        self.home = home
        script = support.appending(path: Self.scriptName)
        states = support.appending(path: "Agents", directoryHint: .isDirectory)
        backups = support.appending(path: "Backups", directoryHint: .isDirectory)
    }

    func configFile(_ tool: AgentTool) -> URL { home.appending(path: tool.configPath) }

    /// Whether the tool is on this Mac: its settings folder exists.
    func isPresent(_ tool: AgentTool) -> Bool {
        FileManager.default.fileExists(atPath: configFile(tool).deletingLastPathComponent().path)
    }

    /// Whether the tool's settings have the notch's hooks.
    func isInstalled(_ tool: AgentTool) -> Bool {
        guard let data = try? Data(contentsOf: configFile(tool)),
            let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return Self.hasOurs(settings)
    }

    public func install(_ tool: AgentTool) throws {
        try FileManager.default.createDirectory(at: states, withIntermediateDirectories: true)
        try writeScript()
        try edit(tool) { Self.adding(tool, command: command, to: $0) }
    }

    /// Takes the tool's hooks out. With no tool left, the script and its session files go too.
    public func uninstall(_ tool: AgentTool) throws {
        try edit(tool) { Self.removing(from: $0) }
        guard !AgentTool.allCases.contains(where: isInstalled) else { return }
        try? FileManager.default.removeItem(at: states)
        try? FileManager.default.removeItem(at: script)
    }

    /// Rewrites the script if an update changed it, so installed hooks run the current one.
    func refreshScript() {
        guard (try? String(contentsOf: script, encoding: .utf8)) != Self.scriptSource else { return }
        try? writeScript()
    }

    private func writeScript() throws {
        try Data(Self.scriptSource.utf8).write(to: script, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    }

    /// Single quotes keep the space in "Application Support" from splitting the command.
    private var command: String { "'\(script.path)'" }

    // MARK: Settings files

    /// Reads a tool's JSON settings (a missing file is an empty one), changes them, and writes them
    /// back atomically with their permissions kept, after saving a backup. A file that exists but
    /// can't be read as a JSON object is never touched.
    private func edit(_ tool: AgentTool, _ change: ([String: Any]) -> [String: Any]) throws {
        let file = configFile(tool)
        let fileManager = FileManager.default
        var settings: [String: Any] = [:]
        var permissions: Any?
        if fileManager.fileExists(atPath: file.path) {
            guard let data = try? Data(contentsOf: file),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { throw AgentHooksError.unreadable("~/" + tool.configPath) }
            settings = object
            permissions = try? fileManager.attributesOfItem(atPath: file.path)[.posixPermissions]
            try fileManager.createDirectory(at: backups, withIntermediateDirectories: true)
            try data.write(to: backups.appending(path: "\(tool.rawValue)-\(file.lastPathComponent)"), options: .atomic)
        }
        let changed = change(settings)
        guard !NSDictionary(dictionary: changed).isEqual(to: settings) else { return }
        // Codex's hooks.json holds only hooks: one ILoveNotch emptied goes, rather than stay empty.
        if tool == .codex, changed.isEmpty {
            try? fileManager.removeItem(at: file)
            return
        }
        try fileManager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: changed, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: file, options: .atomic)
        if let permissions { try? fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: file.path) }
    }

    static func isOurs(_ handler: Any) -> Bool {
        ((handler as? [String: Any])?["command"] as? String)?.contains(scriptName) == true
    }

    static func hasOurs(_ settings: [String: Any]) -> Bool {
        let events = settings["hooks"] as? [String: Any] ?? [:]
        return events.values.contains { groups in
            (groups as? [Any] ?? []).contains {
                (($0 as? [String: Any])?["hooks"] as? [Any] ?? []).contains(where: isOurs)
            }
        }
    }

    /// `settings` with the notch's hooks for `tool` after everyone else's, one group per event. It
    /// runs in the background (`async`), so an agent never waits on it.
    static func adding(_ tool: AgentTool, command: String, to settings: [String: Any]) -> [String: Any] {
        var settings = removing(from: settings)
        var events = settings["hooks"] as? [String: Any] ?? [:]
        for (event, matcher, state) in tool.events {
            var group: [String: Any] = [
                "hooks": [["type": "command", "command": "\(command) \(tool.rawValue) \(state)", "async": true]]
            ]
            if let matcher { group["matcher"] = matcher }
            events[event] = (events[event] as? [Any] ?? []) + [group]
        }
        settings["hooks"] = events
        return settings
    }

    /// `settings` without the notch's hooks. Groups, events, and a `hooks` key left empty go too;
    /// everything else stays as it was.
    static func removing(from settings: [String: Any]) -> [String: Any] {
        guard let events = settings["hooks"] as? [String: Any] else { return settings }
        var kept: [String: Any] = [:]
        for (event, value) in events {
            guard let groups = value as? [Any] else {
                kept[event] = value
                continue
            }
            let remaining = groups.compactMap { group -> Any? in
                guard var group = group as? [String: Any], let handlers = group["hooks"] as? [Any],
                    handlers.contains(where: isOurs)
                else { return group }
                let others = handlers.filter { !isOurs($0) }
                if others.isEmpty { return nil }
                group["hooks"] = others
                return group
            }
            if !remaining.isEmpty { kept[event] = remaining }
        }
        var settings = settings
        settings["hooks"] = kept.isEmpty ? nil : kept
        return settings
    }

    // MARK: The hook script

    /// Runs on the agent's hook events. It writes one small file per session beside itself: the
    /// state, the project folder, the app the agent runs in, its process, and what it's waiting
    /// for. Never the prompt or any code, and nothing leaves the Mac. `plutil` reads the hook's
    /// JSON, since macOS 14 has no `jq`. It never blocks the agent and always exits 0.
    static let scriptSource = #"""
        #!/bin/sh
        # ILoveNotch agent status, run by Claude Code's and Codex's hooks. ILoveNotch adds the hooks
        # when you connect a tool in Settings > Agents and removes them when you disconnect.
        # Usage: ilovenotch-agent-hook <claude|codex> <working|waiting|resumed|done|ended> < hook.json
        tool=$1
        event=$2
        dir="$(dirname "$0")/Agents"
        if [ ! -d "$dir" ]; then cat >/dev/null; exit 0; fi
        # After every tool call: only worth reading while one of this tool's sessions is waiting.
        if [ "$event" = resumed ] && ! grep -qsx waiting "$dir/$tool"-*; then cat >/dev/null; exit 0; fi
        input=$(cat)
        field() { printf '%s' "$input" | /usr/bin/plutil -extract "$1" raw -o - - 2>/dev/null | tr '\n\r' '  '; }
        session=$(field session_id | tr -cd 'A-Za-z0-9._-')
        [ -n "$session" ] || exit 0
        file="$dir/$tool-$session"
        case $event in
        ended) rm -f "$file"; exit 0 ;;
        resumed) [ "$(head -n 1 "$file" 2>/dev/null)" = waiting ] || exit 0; state=working ;;
        working | waiting | done) state=$event ;;
        *) exit 0 ;;
        esac
        tmp=$(mktemp "$dir/.$tool.XXXXXX") || exit 0
        {
            printf '%s\n' "$state" "$(field cwd)" "${__CFBundleIdentifier:-}" "${TERM_PROGRAM:-}" "$PPID"
            printf '%s\n' "$(field message)" "$(field tool_name)"
        } >"$tmp"
        mv -f "$tmp" "$file"
        exit 0

        """#
}
