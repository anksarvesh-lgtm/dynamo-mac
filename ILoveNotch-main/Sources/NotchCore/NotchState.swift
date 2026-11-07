// SPDX-License-Identifier: MIT
import Foundation

/// A feature that can own the expanded notch.
public enum FeatureID: String, CaseIterable, Hashable, Sendable {
    case media, sound, shelf, clipboard, calendar, tasks, notes, shortcuts, timer, network, mirror, usage, agents

    /// SF Symbol for the tab's page in Settings, beside System Settings' own symbols. The notch draws
    /// Tabler icons instead (NotchSurface's `FeatureID.icon`). Every name here exists on macOS 14.6,
    /// the oldest supported.
    public var symbol: String {
        switch self {
        case .media: "play.circle"
        case .sound: "speaker.wave.2"
        case .shelf: "tray.full"
        case .clipboard: "list.clipboard"
        case .calendar: Self.today
        case .tasks: "checklist"
        case .notes: "note.text"
        case .shortcuts: "square.2.layers.3d"
        case .timer: "timer"
        case .network: "arrow.up.arrow.down.circle"
        case .mirror: "web.camera"
        case .usage: "gauge.with.needle"
        case .agents: "apple.terminal"
        }
    }

    /// Today's date on a calendar page, like the Calendar app's icon, where macOS has those symbols.
    private static var today: String {
        guard #available(macOS 26, *) else { return "calendar" }
        return "\(Calendar.current.component(.day, from: .now)).calendar"
    }

    public var title: String {
        switch self {
        case .media: "Media"
        case .sound: "Sound"
        case .shelf: "Shelf"
        case .clipboard: "Clipboard"
        case .calendar: "Calendar"
        case .tasks: "Tasks"
        case .notes: "Notes"
        case .shortcuts: "Shortcuts"
        case .timer: "Timer"
        case .network: "Network"
        case .mirror: "Mirror"
        case .usage: "AI Usage"
        case .agents: "Agents"
        }
    }
}

/// A live activity shown on the compact notch: one-shot, such as a track change, a file drop, or
/// the volume changing, or ongoing, such as a meeting about to start, until its feature clears it.
public struct Activity: Hashable, Sendable {
    /// The tab that raised it, which opens when it's hovered or clicked. Nil for a system activity,
    /// such as volume or battery, that belongs to no tab and shows whatever tabs are enabled.
    public var feature: FeatureID?
    /// SF Symbol shown just before the title.
    public var symbol: String
    /// Short text: under the camera for a one-shot activity, beside it for an ongoing one.
    public var title: String
    /// 0...1 for a meter beside the title, such as the volume or the battery's charge.
    public var level: Double?
    /// How long a one-shot activity shows. Ongoing activities ignore it.
    public var duration: Duration
    /// Shown instead of the title: the time left until this moment, ticking down to 0:00.
    public var countdown: Date?
    /// A small encoded image shown in place of the symbol, such as the cover of what's playing.
    public var artwork: Data?

    public init(
        feature: FeatureID?, symbol: String, title: String, level: Double? = nil, duration: Duration,
        countdown: Date? = nil, artwork: Data? = nil
    ) {
        self.feature = feature
        self.symbol = symbol
        self.title = title
        self.level = level
        self.duration = duration
        self.countdown = countdown
        self.artwork = artwork
    }
}

/// Why the notch is out of the way. Reasons overlap (a Mac can sleep while locked), so the
/// notch comes back only once every reason has cleared.
public enum SuspendReason: Hashable, Sendable {
    case systemSleep
    case displaySleep
    case screenLocked
    /// A full-screen app fills the display, as it does on one without a notch.
    case fullScreen
}

/// Everything the notch can be doing. One value replaces the prototype's `isOpen` flag,
/// so contradictory combinations (pinned but closed, focused while hidden) can't exist.
public enum NotchPresentationState: Hashable, Sendable {
    /// Not attached to a display.
    case hidden
    /// Resting: a black lip around the physical notch.
    case compact
    /// The pointer is on the notch; it expands once `NotchTiming.hoverDwell` passes.
    case hoverArmed
    /// Open while in use; collapses `NotchTiming.collapseGrace` after the pointer leaves.
    case expanded(tab: FeatureID)
    /// Open until dismissed; ignores the pointer leaving and click-away.
    case pinned(tab: FeatureID)
    /// Taking text input. Stays open and remembers whether it was pinned.
    case focused(tab: FeatureID, pinned: Bool)
    /// Showing a live activity on the compact notch.
    case transient(Activity)
    /// Out of the way: sleep, display sleep, screen lock, or a full-screen app.
    case suspended

    /// The tab on screen when the notch is open.
    public var openTab: FeatureID? {
        switch self {
        case .expanded(let tab), .pinned(let tab), .focused(let tab, _): tab
        default: nil
        }
    }

    /// Whether the notch stays open when the pointer leaves or the user clicks elsewhere.
    public var isPinned: Bool {
        switch self {
        case .pinned, .focused(_, true): true
        default: false
        }
    }

    /// The one deadline this state may have pending.
    var deadline: Deadline? {
        switch self {
        case .hoverArmed: .hoverDwell
        case .expanded: .collapseGrace
        case .transient: .activityEnd
        default: nil
        }
    }
}

/// Inputs to the reducer. Pointer, keyboard, feature, and system callbacks all become one of these.
public enum NotchEvent: Hashable, Sendable {
    case show
    case hide
    case pointerEntered
    case pointerExited
    /// Primary click (or a pull-down scroll) on the notch itself.
    case clicked
    /// Click anywhere outside the notch.
    case clickedOutside
    /// Escape or a close control.
    case dismiss
    case selectTab(FeatureID)
    case togglePin
    case beginTextInput
    case endTextInput
    /// Files are being dragged over the notch.
    case dragEntered
    case dragExited
    /// Files were dropped on the notch.
    case dropped
    case activity(Activity)
    /// The activity the resting notch shows until it's replaced or cleared (nil).
    case setOngoing(Activity?)
    /// The enabled features changed, in tab order.
    case setTabs([FeatureID])
    case suspend(SuspendReason)
    case resume(SuspendReason)
    /// A deadline requested by an earlier `NotchEffect.schedule` fired.
    case deadline(Deadline)
}

/// Timers the reducer can ask for. Each belongs to exactly one presentation state.
public enum Deadline: Hashable, Sendable {
    case hoverDwell
    case collapseGrace
    case activityEnd
}

/// Work the reducer asks its runner to do. Scheduling a pending deadline replaces it.
public enum NotchEffect: Hashable, Sendable {
    case schedule(Deadline, after: Duration)
    case cancel(Deadline)
}

/// Pointer hysteresis timings.
public enum NotchTiming {
    // ponytail: hand-picked defaults; calibrate on hardware with the Phase 2 surface.
    /// How long the pointer rests on the notch before it expands.
    public static let hoverDwell: Duration = .milliseconds(100)
    /// How long the pointer may stray from the expanded notch before it collapses.
    public static let collapseGrace: Duration = .milliseconds(250)
}

/// The reducer's whole world: the presentation plus the facts it must carry across states.
public struct NotchState: Hashable, Sendable {
    public private(set) var presentation: NotchPresentationState = .hidden
    /// The tab to show the next time the notch expands. Always one of `tabs` when any exist.
    public private(set) var lastTab: FeatureID = .media
    /// Enabled features in tab order. The notch never opens a tab missing from this list.
    public private(set) var tabs: [FeatureID] = FeatureID.allCases
    /// Every reason the notch is currently suspended.
    public private(set) var suspensions: Set<SuspendReason> = []
    /// Kept in every state so a late collapse deadline can't close a notch the pointer is on.
    public private(set) var pointerInside = false
    /// Shown by the resting notch instead of hiding behind the camera housing, while its feature
    /// is enabled. One-shot activities show over it.
    public private(set) var ongoing: Activity?

    public init() {}

    /// The ongoing activity the notch shows right now: while it rests, and while the pointer is on it
    /// on the way to opening (so the notch doesn't shrink out from under the pointer), and only for
    /// an enabled feature.
    public var restingActivity: Activity? {
        guard presentation == .compact || presentation == .hoverArmed, let ongoing, shows(ongoing) else { return nil }
        return ongoing
    }

    /// Applies one event and returns the effects to run. Pure: no clocks, no I/O.
    public mutating func handle(_ event: NotchEvent) -> [NotchEffect] {
        switch event {
        case .pointerEntered, .dragEntered, .dropped: pointerInside = true
        case .pointerExited, .dragExited: pointerInside = false
        default: break
        }
        let before = presentation
        var effects = transition(on: event)
        // Leaving a state cancels the deadline it owned, so at most one deadline is ever pending.
        if let owned = before.deadline, owned != presentation.deadline, event != .deadline(owned) {
            effects.insert(.cancel(owned), at: 0)
        }
        return effects
    }

    /// Every (state, event) pair not listed here is deliberately a no-op, including late deadlines.
    private mutating func transition(on event: NotchEvent) -> [NotchEffect] {
        switch (presentation, event) {
        // Settings apply in every state.
        case (_, .setTabs(let enabled)):
            tabs = enabled
            if !tabs.contains(lastTab), let first = tabs.first { lastTab = first }
            switch presentation {
            case .expanded(let tab), .pinned(let tab), .focused(let tab, _):
                guard !tabs.contains(tab) else { break }
                if let first = tabs.first {
                    open(first, pinned: presentation.isPinned)
                } else {
                    presentation = .compact
                }
            case .transient(let activity) where !shows(activity):
                presentation = .compact
            case .hoverArmed where tabs.isEmpty:
                presentation = .compact
            default:
                break
            }
        case (_, .setOngoing(let activity)):
            ongoing = activity

        // Suspending, attaching, and detaching win over everything else.
        case (_, .suspend(let reason)):
            suspensions.insert(reason)
            if presentation != .hidden {
                presentation = .suspended
                pointerInside = false
            }
        case (_, .resume(let reason)):
            suspensions.remove(reason)
            if presentation == .suspended, suspensions.isEmpty { presentation = .compact }
        case (.hidden, .show):
            presentation = suspensions.isEmpty ? .compact : .suspended
        case (.hidden, _):
            break
        case (_, .hide):
            presentation = .hidden
            pointerInside = false
        case (.suspended, _):
            break

        // Opening; with no tabs enabled there is nothing to open, so hovering doesn't arm. Like a
        // live activity, an ongoing one opens the feature that shows it.
        case (.compact, .pointerEntered) where !tabs.isEmpty:
            lastTab = restingActivity?.feature ?? lastTab
            presentation = .hoverArmed
            return [.schedule(.hoverDwell, after: NotchTiming.hoverDwell)]
        case (.compact, .clicked):
            open(restingActivity?.feature ?? lastTab)
        case (.transient(let activity), .pointerEntered) where !tabs.isEmpty:
            // Hovering a live activity opens the feature that raised it, or the last tab for a
            // system activity.
            lastTab = activity.feature ?? lastTab
            presentation = .hoverArmed
            return [.schedule(.hoverDwell, after: NotchTiming.hoverDwell)]
        case (.hoverArmed, .clicked), (.hoverArmed, .deadline(.hoverDwell)):
            open(lastTab)
        case (.transient(let activity), .clicked):
            open(activity.feature ?? lastTab)
        case (.hoverArmed, .pointerExited), (.hoverArmed, .dragExited), (.hoverArmed, .dismiss):
            presentation = .compact

        // Dragging files over the notch opens the shelf to catch them.
        case (.focused(_, let pinned), .dragEntered) where tabs.contains(.shelf):
            presentation = .focused(tab: .shelf, pinned: pinned)
            lastTab = .shelf
        case (_, .dragEntered) where tabs.contains(.shelf):
            let hadGrace = presentation.deadline == .collapseGrace
            open(.shelf, pinned: presentation.isPinned)
            return hadGrace ? [.cancel(.collapseGrace)] : []
        case (.expanded, .dragExited):
            return [.schedule(.collapseGrace, after: NotchTiming.collapseGrace)]
        case (.expanded, .dropped):
            return [.cancel(.collapseGrace)]

        // Live activities show only while the notch is closed, and only for enabled features.
        case (.compact, .activity(let activity)) where shows(activity),
            (.transient, .activity(let activity)) where shows(activity):
            presentation = .transient(activity)
            return [.schedule(.activityEnd, after: activity.duration)]
        case (.transient, .deadline(.activityEnd)), (.transient, .dismiss):
            presentation = .compact

        // Expanded
        case (.expanded, .pointerEntered):
            return [.cancel(.collapseGrace)]
        case (.expanded, .pointerExited):
            return [.schedule(.collapseGrace, after: NotchTiming.collapseGrace)]
        case (.expanded, .deadline(.collapseGrace)) where !pointerInside:
            presentation = .compact
        case (.expanded, .clickedOutside), (.expanded, .dismiss):
            presentation = .compact
        case (.expanded(let tab), .togglePin):
            open(tab, pinned: true)
        case (.expanded(let tab), .beginTextInput):
            presentation = .focused(tab: tab, pinned: false)

        // Pinned
        case (.pinned(let tab), .togglePin):
            open(tab)
        case (.pinned(let tab), .beginTextInput):
            presentation = .focused(tab: tab, pinned: true)
        case (.pinned, .dismiss):
            presentation = .compact

        // Focused
        case (.focused(let tab, let pinned), .endTextInput):
            open(tab, pinned: pinned)
        case (.focused(let tab, let pinned), .togglePin):
            presentation = .focused(tab: tab, pinned: !pinned)
        case (.focused(let tab, true), .clickedOutside):
            open(tab, pinned: true)
        case (.focused, .clickedOutside), (.focused, .dismiss):
            presentation = .compact

        // Choosing a tab opens it and keeps a pin. While the notch has the keyboard, switching tabs
        // keeps focus too: text entry ends only when the panel loses the keyboard or is dismissed.
        case (.focused(_, let pinned), .selectTab(let tab)) where tabs.contains(tab):
            lastTab = tab
            presentation = .focused(tab: tab, pinned: pinned)
        case (_, .selectTab(let tab)):
            open(tab, pinned: presentation.isPinned)

        default:
            break
        }
        return []
    }

    /// A feature's activity shows while its tab is enabled; a system activity always does.
    private func shows(_ activity: Activity) -> Bool {
        activity.feature.map(tabs.contains) ?? true
    }

    /// Opens `tab`, or the first enabled tab if `tab` is disabled. With no tabs enabled, nothing opens.
    private mutating func open(_ tab: FeatureID, pinned: Bool = false) {
        guard let tab = tabs.contains(tab) ? tab : tabs.first else { return }
        lastTab = tab
        presentation = pinned ? .pinned(tab: tab) : .expanded(tab: tab)
    }
}
