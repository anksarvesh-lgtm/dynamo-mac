// SPDX-License-Identifier: MIT
import EventKit
import NotchCore
import Observation
import SwiftUI

/// One reminder, copied out of EventKit so it can cross threads.
public struct TaskItem: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var due: Date?
    /// Whether `due` has a time of day; without one the task is due on a day.
    public var hasTime = false
    /// When it was completed; nil while it's open.
    public var completed: Date?
    public var color: RGB?
    public var priority: TaskPriority = .none
    public var listID: String?
    public var listTitle: String?
    public var repeats = false
    /// Whether Reminders will notify at a set time.
    public var hasAlert = false

    init(_ reminder: EKReminder) {
        id = reminder.calendarItemIdentifier
        title = reminder.title ?? "Untitled"
        let components = reminder.dueDateComponents
        due = components.flatMap { Calendar.current.date(from: $0) }
        hasTime = components?.hour != nil
        completed = reminder.isCompleted ? reminder.completionDate ?? .distantPast : nil
        color = RGB(reminder.calendar?.cgColor)
        priority = TaskPriority(eventKit: reminder.priority)
        listID = reminder.calendar?.calendarIdentifier
        listTitle = reminder.calendar?.title
        repeats = reminder.hasRecurrenceRules
        hasAlert = reminder.alarms?.contains { $0.structuredLocation == nil } ?? false
    }

    init(
        id: String, title: String, due: Date? = nil, hasTime: Bool = false, completed: Date? = nil,
        priority: TaskPriority = .none, listTitle: String? = nil
    ) {
        self.id = id
        self.title = title
        self.due = due
        self.hasTime = hasTime
        self.completed = completed
        self.priority = priority
        self.listTitle = listTitle
    }

    public func group(now: Date = .now) -> TaskGroup { TaskGroup(due: due, hasTime: hasTime, now: now) }

    public func isOverdue(now: Date = .now) -> Bool { group(now: now) == .overdue }

    /// Soonest due first, undated last, then the highest priority, then by title.
    static func order(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        switch (lhs.due, rhs.due) {
        case (let left?, let right?) where left != right: return left < right
        case (.some, nil): return true
        case (nil, .some): return false
        default:
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    /// Most recently completed first.
    static func recentlyCompletedFirst(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        (lhs.completed ?? .distantPast) > (rhs.completed ?? .distantPast)
    }

    /// When a block of time for this task starts: its due time if that's still ahead, otherwise the
    /// next quarter hour.
    static func blockStart(for task: TaskItem, now: Date) -> Date {
        if task.hasTime, let due = task.due, due > now { return due }
        let quarter: TimeInterval = 15 * 60
        let quarters = (now.timeIntervalSinceReferenceDate / quarter).rounded(.up)
        return Date(timeIntervalSinceReferenceDate: quarters * quarter)
    }
}

/// A Reminders list the user can pick in settings.
public struct ReminderList: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var color: RGB?
}

/// A run of tasks under one heading: a date group, or a list.
public struct TaskSection: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var color: RGB?
    /// Whether this is the Overdue group, which is drawn in red.
    public var isOverdue = false
    public var tasks: [TaskItem]
}

/// Quick picks for a task's due date.
public enum DueChoice: String, CaseIterable, Identifiable, Sendable {
    case today
    case tomorrow
    case weekend
    case nextWeek
    case none

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        case .weekend: "This Weekend"
        case .nextWeek: "Next Week"
        case .none: "No Date"
        }
    }

    /// The day this choice means, keeping the time of day from `current` when there is one.
    func date(from now: Date, keeping current: Date?, hasTime: Bool, calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: now)
        let day: Date?
        switch self {
        case .today: day = today
        case .tomorrow: day = calendar.date(byAdding: .day, value: 1, to: today)
        case .weekend:
            let saturday = calendar.nextDate(
                after: now, matching: DateComponents(weekday: 7), matchingPolicy: .nextTime)
            day = calendar.isDateInWeekend(now) ? today : saturday.map(calendar.startOfDay(for:))
        case .nextWeek:
            let start = DateComponents(weekday: calendar.firstWeekday)  // the start of the user's week
            let next = calendar.nextDate(after: now, matching: start, matchingPolicy: .nextTime)
            day = next.map(calendar.startOfDay(for:))
        case .none: return nil
        }
        guard let day else { return nil }
        guard hasTime, let current else { return day }
        let time = calendar.dateComponents([.hour, .minute], from: current)
        return calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: day)
    }
}

/// Reminders from Apple Reminders, so tasks sync to the iPhone over iCloud with no server: the open
/// ones grouped by date or list, plus a collapsible section of recently completed ones. Access is
/// asked for only on tap. Reads happen only while the tab is on screen and refresh on EventKit's
/// change notification; in the background it only waits for the next task due at a set time, so it
/// can show it on the notch.
@MainActor
@Observable
public final class TasksFeature: NotchFeature {
    public let id = FeatureID.tasks
    public var phase: FeaturePhase = .stopped {
        didSet {
            guard phase != oldValue else { return }
            updateWork()
        }
    }
    public private(set) var access = EventAccess(.reminder)
    public private(set) var tasks: [TaskItem] = []
    /// Completed in the last `completedWindow`, newest first, at most `completedLimit`.
    public private(set) var completed: [TaskItem] = []
    public private(set) var lists: [ReminderList] = []
    /// A task whose due time just arrived, shown at the top of the tab until handled.
    public private(set) var alerting: TaskItem?
    /// A short confirmation or problem, such as "Blocked 30 min at 3:00 PM". Clears itself.
    public private(set) var notice: String?
    /// Per-feature setting: the list to show and add to. Nil shows every list and adds to the default.
    public var listID: String? {
        didSet {
            defaults.set(listID, forKey: Self.listKey)
            reload()
            scheduleNextAlert()
        }
    }
    /// Whether the completed section is expanded.
    public var showsCompleted: Bool {
        didSet { defaults.set(showsCompleted, forKey: Self.showsCompletedKey) }
    }
    /// Group open tasks by Reminders list instead of by when they're due.
    public var groupsByList: Bool {
        didSet { defaults.set(groupsByList, forKey: Self.groupsByListKey) }
    }
    /// Tasks dragged into place, by ID: a section shows these first, in this order, then the rest
    /// soonest due first. Reminders keeps its own manual order where EventKit can't read it, so this
    /// one stays on this Mac.
    public private(set) var manualOrder: [String] {
        didSet { defaults.set(manualOrder, forKey: Self.manualOrderKey) }
    }
    /// Show a task on the notch when its due time arrives.
    public var alertsInNotch: Bool {
        didSet {
            defaults.set(alertsInNotch, forKey: Self.alertsInNotchKey)
            updateWork()
        }
    }
    /// Give new tasks with a due time an alert at that time, which Reminders delivers on every device.
    public var alertsAtDueTime: Bool {
        didSet { defaults.set(alertsAtDueTime, forKey: Self.alertsAtDueTimeKey) }
    }
    /// How long a block of time made from a task lasts, in minutes.
    public var blockMinutes: Int {
        didSet { defaults.set(blockMinutes, forKey: Self.blockMinutesKey) }
    }
    /// Raised when a task comes due.
    @ObservationIgnored public var onActivity: ((Activity) -> Void)?

    // ponytail: completed tasks are bounded by age and count so years of history can't flood the notch.
    static let completedWindow = 30  // days
    nonisolated static let completedLimit = 50
    static let snoozeMinutes = 10
    private static let listKey = "tasks.listID"
    private static let showsCompletedKey = "tasks.showsCompleted"
    private static let groupsByListKey = "tasks.groupsByList"
    private static let manualOrderKey = "tasks.manualOrder"
    private static let alertsInNotchKey = "tasks.alertsInNotch"
    private static let alertsAtDueTimeKey = "tasks.alertsAtDueTime"
    private static let blockMinutesKey = "tasks.blockMinutes"
    @ObservationIgnored private let eventStore: EventStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var changes: NSObjectProtocol?
    @ObservationIgnored private var nextAlert: Task<Void, Never>?
    @ObservationIgnored private var clearNotice: Task<Void, Never>?

    public init(eventStore: EventStore, defaults: UserDefaults = .standard) {
        self.eventStore = eventStore
        self.defaults = defaults
        listID = defaults.string(forKey: Self.listKey)
        showsCompleted = defaults.bool(forKey: Self.showsCompletedKey)
        groupsByList = defaults.bool(forKey: Self.groupsByListKey)
        manualOrder = defaults.stringArray(forKey: Self.manualOrderKey) ?? []
        alertsInNotch = defaults.object(forKey: Self.alertsInNotchKey) as? Bool ?? true
        alertsAtDueTime = defaults.object(forKey: Self.alertsAtDueTimeKey) as? Bool ?? true
        let minutes = defaults.integer(forKey: Self.blockMinutesKey)
        blockMinutes = minutes > 0 ? minutes : 30
    }

    public var view: some View { TasksView(tasks: self) }

    /// Whether the feature is listening for reminder changes.
    var isObserving: Bool { changes != nil }

    /// Open tasks under headings: by date (Overdue, Today, Tomorrow, …) or by list. Each keeps the
    /// order tasks were dragged into, if any.
    public func sections(now: Date = .now) -> [TaskSection] {
        let rank = Dictionary(manualOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: min)
        // The sort is stable, so tasks never dragged keep their date order after the ones that were.
        let tasks = self.tasks.sorted { rank[$0.id, default: .max] < rank[$1.id, default: .max] }
        if groupsByList {
            let byList = Dictionary(grouping: tasks) { $0.listID ?? $0.listTitle ?? "" }
            let known = lists.map(\.id).filter { byList[$0] != nil }
            let order = known + byList.keys.filter { !known.contains($0) }.sorted()
            return order.compactMap { id in
                guard let items = byList[id], let first = items.first else { return nil }
                let list = lists.first { $0.id == id }
                return TaskSection(
                    id: "list-\(id)", title: list?.title ?? first.listTitle ?? "Other",
                    color: list?.color ?? first.color, tasks: items)
            }
        }
        let byGroup = Dictionary(grouping: tasks) { $0.group(now: now) }
        return TaskGroup.allCases.compactMap { group in
            guard let items = byGroup[group] else { return nil }
            return TaskSection(
                id: "group-\(group.rawValue)", title: group.title, isOverdue: group == .overdue, tasks: items)
        }
    }

    /// Puts a task where `target` is in their section, as a drag drops it there. The section keeps
    /// that order from then on, and a task added later joins at its end, as in Reminders. Tasks in
    /// different sections stay put.
    public func move(_ task: TaskItem, to target: TaskItem, now: Date = .now) {
        guard
            var order = sections(now: now).first(where: { $0.tasks.contains { $0.id == target.id } })?.tasks.map(\.id),
            let from = order.firstIndex(of: task.id), let to = order.firstIndex(of: target.id), from != to
        else { return }
        order.move(fromOffsets: [from], toOffset: to > from ? to + 1 : to)
        let placed = Set(order)
        let open = Set(tasks.map(\.id))
        manualOrder = manualOrder.filter { open.contains($0) && !placed.contains($0) } + order
    }

    public func requestAccess() {
        eventStore.store.requestFullAccessToReminders { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.access = EventAccess(.reminder)
                self.updateWork()
            }
        }
    }

    /// Marks a task done; it moves to the completed section.
    public func complete(_ task: TaskItem) {
        if alerting?.id == task.id { alerting = nil }
        guard edit(task, { $0.isCompleted = true }) else { return }
        tasks.removeAll { $0.id == task.id }
        var done = task
        done.completed = .now
        completed.insert(done, at: 0)
    }

    /// Marks a completed task open again.
    public func reopen(_ task: TaskItem) {
        guard edit(task, { $0.isCompleted = false }) else { return }
        completed.removeAll { $0.id == task.id }
        var open = task
        open.completed = nil
        tasks = (tasks + [open]).sorted(by: TaskItem.order)
    }

    /// Adds a task from a quick-add line such as "Call Sam tomorrow 5pm !! #Work". Returns whether
    /// it was saved.
    @discardableResult
    public func add(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, EventAccess(.reminder) == .granted else { return false }
        let draft = TaskDraft.parse(text)
        let store = eventStore.store
        let reminder = EKReminder(eventStore: store)
        reminder.title = draft.title
        let named = draft.list.flatMap { name in
            store.calendars(for: .reminder).first { Self.listName($0.title, matches: name) }
        }
        if named == nil, let list = draft.list { reminder.title = "\(draft.title) #\(list)" }
        reminder.calendar =
            named ?? listID.flatMap(store.calendar(withIdentifier:)) ?? store.defaultCalendarForNewReminders()
        reminder.priority = draft.priority.eventKitValue
        Self.setDue(draft.due, hasTime: draft.hasTime, alert: alertsAtDueTime, on: reminder)
        if let repeats = draft.repeats {
            reminder.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: repeats.frequency, interval: 1, end: nil))
        }
        do {
            try store.save(reminder, commit: true)
        } catch {
            Log.features.error("Couldn't add a reminder: \(error.localizedDescription, privacy: .public)")
            return false
        }
        reload()
        scheduleNextAlert()
        return true
    }

    public func rename(_ task: TaskItem, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != task.title else { return }
        change(task) { $0.title = title }
    }

    public func setDue(_ task: TaskItem, to choice: DueChoice) {
        let due = choice.date(from: .now, keeping: task.due, hasTime: task.hasTime)
        let alert = task.hasAlert || alertsAtDueTime
        change(task) { Self.setDue(due, hasTime: task.hasTime && due != nil, alert: alert, on: $0) }
    }

    public func setPriority(_ task: TaskItem, to priority: TaskPriority) {
        change(task) { $0.priority = priority.eventKitValue }
    }

    public func move(_ task: TaskItem, toList id: String) {
        guard let list = eventStore.store.calendar(withIdentifier: id) else { return }
        change(task) { $0.calendar = list }
    }

    public func delete(_ task: TaskItem) {
        let store = eventStore.store
        guard let reminder = store.calendarItem(withIdentifier: task.id) as? EKReminder else { return }
        if alerting?.id == task.id { alerting = nil }
        do {
            try store.remove(reminder, commit: true)
            tasks.removeAll { $0.id == task.id }
            completed.removeAll { $0.id == task.id }
        } catch {
            Log.features.error("Couldn't delete a reminder: \(error.localizedDescription, privacy: .public)")
        }
        scheduleNextAlert()
    }

    /// Moves the due time a few minutes on, with an alert then.
    public func snooze(_ task: TaskItem) {
        if alerting?.id == task.id { alerting = nil }
        let due = Date.now.addingTimeInterval(TimeInterval(Self.snoozeMinutes * 60))
        change(task) { Self.setDue(due, hasTime: true, alert: true, on: $0) }
        show(notice: "Snoozed for \(Self.snoozeMinutes) min")
    }

    public func dismissAlert() { alerting = nil }

    /// Sets aside time for a task in Calendar: at its due time if that's ahead, or the next quarter
    /// hour. Asks for calendar access the first time.
    public func blockTime(for task: TaskItem) {
        switch EventAccess(.event) {
        case .granted:
            addBlock(for: task)
        case .notDetermined:
            eventStore.store.requestFullAccessToEvents { [weak self] granted, _ in
                Task { @MainActor in
                    guard let self else { return }
                    if granted {
                        self.addBlock(for: task)
                    } else {
                        self.show(notice: "Calendar access is off")
                    }
                }
            }
        case .denied:
            show(notice: "Allow Calendars access in System Settings to block time")
        }
    }

    /// Re-reads access, which may have changed in System Settings.
    public func refreshAccess() { access = EventAccess(.reminder) }

    /// Loads the Reminders lists, for the settings picker as well as the tab.
    public func loadLists() {
        guard EventAccess(.reminder) == .granted else { return }
        lists = eventStore.store.calendars(for: .reminder)
            .map { ReminderList(id: $0.calendarIdentifier, title: $0.title, color: RGB($0.cgColor)) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Shows the given tasks as if access were granted. For tests and snapshots only.
    func show(tasks: [TaskItem], completed: [TaskItem], alerting: TaskItem? = nil) {
        access = .granted
        self.tasks = tasks
        self.completed = completed
        self.alerting = alerting
    }

    /// "#work" or "#WorkStuff" picks "Work Stuff": case and spaces don't matter.
    static func listName(_ title: String, matches name: String) -> Bool {
        let squashed = { (text: String) in text.replacingOccurrences(of: " ", with: "").lowercased() }
        return squashed(title) == squashed(name)
    }

    /// Sets a reminder's due date, replacing its timed alerts (location alerts stay). A task due on a
    /// day gets no alert of its own: Reminders notifies about those at the time set in its settings.
    private static func setDue(_ due: Date?, hasTime: Bool, alert: Bool, on reminder: EKReminder) {
        if let due {
            let units: Set<Calendar.Component> =
                hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
            reminder.dueDateComponents = Calendar.current.dateComponents(units, from: due)
        } else {
            reminder.dueDateComponents = nil
        }
        for alarm in reminder.alarms ?? [] where alarm.structuredLocation == nil {
            reminder.removeAlarm(alarm)
        }
        if alert, hasTime, let due { reminder.addAlarm(EKAlarm(absoluteDate: due)) }
    }

    /// Applies a change to the stored reminder, then reloads. Returns whether it was saved.
    @discardableResult
    private func change(_ task: TaskItem, _ apply: (EKReminder) -> Void) -> Bool {
        guard edit(task, apply) else { return false }
        reload()
        scheduleNextAlert()
        return true
    }

    private func edit(_ task: TaskItem, _ apply: (EKReminder) -> Void) -> Bool {
        let store = eventStore.store
        guard let reminder = store.calendarItem(withIdentifier: task.id) as? EKReminder else { return false }
        apply(reminder)
        do {
            try store.save(reminder, commit: true)
            return true
        } catch {
            Log.features.error("Couldn't update a reminder: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func addBlock(for task: TaskItem) {
        let store = eventStore.store
        guard let calendar = store.defaultCalendarForNewEvents else {
            show(notice: "No calendar to add the block to")
            return
        }
        let event = EKEvent(eventStore: store)
        event.title = task.title
        event.calendar = calendar
        event.startDate = TaskItem.blockStart(for: task, now: .now)
        event.endDate = event.startDate.addingTimeInterval(TimeInterval(blockMinutes * 60))
        event.notes = "Time set aside for a task from Reminders."
        do {
            try store.save(event, span: .thisEvent, commit: true)
            let time = event.startDate.formatted(date: .omitted, time: .shortened)
            show(notice: "Blocked \(blockMinutes) min at \(time)")
        } catch {
            Log.features.error("Couldn't add a time block: \(error.localizedDescription, privacy: .public)")
            show(notice: "Couldn't add it to Calendar")
        }
    }

    private func show(notice text: String) {
        notice = text
        clearNotice?.cancel()
        clearNotice = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            self?.notice = nil
        }
    }

    /// Starts or stops the work each phase allows: on screen, reading and watching reminders; in the
    /// background, only waiting for the next due time, and only while notch alerts are on.
    private func updateWork() {
        refreshAccess()
        let watching = access == .granted && (phase == .foreground || (phase == .background && alertsInNotch))
        if watching, changes == nil {
            changes = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged, object: eventStore.store, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reload()
                    self?.scheduleNextAlert()
                }
            }
        } else if !watching, let changes {
            NotificationCenter.default.removeObserver(changes)
            self.changes = nil
        }
        if phase != .foreground {
            tasks = []
            completed = []
        }
        if phase == .stopped { alerting = nil }
        reload()
        scheduleNextAlert()
    }

    private var chosenLists: [EKCalendar]? {
        listID.flatMap(eventStore.store.calendar(withIdentifier:)).map { [$0] }
    }

    private func reload() {
        guard access == .granted, phase == .foreground else { return }
        let store = eventStore.store
        loadLists()
        let chosen = chosenLists
        let open = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: chosen)
        // EventKit calls back on its own queue: @Sendable keeps these closures off the main actor,
        // or Swift 6 traps the first time a main-actor closure inside them runs there.
        store.fetchReminders(matching: open) { @Sendable [weak self] reminders in
            let items = (reminders ?? []).map(TaskItem.init).sorted(by: TaskItem.order)
            Task { @MainActor in
                // Results that land after the tab went away are dropped, not kept in memory.
                guard let self, self.phase == .foreground else { return }
                self.tasks = items
            }
        }
        let since = Calendar.current.date(byAdding: .day, value: -Self.completedWindow, to: .now)
        let done = store.predicateForCompletedReminders(
            withCompletionDateStarting: since, ending: nil, calendars: chosen)
        store.fetchReminders(matching: done) { @Sendable [weak self] reminders in
            let items = (reminders ?? []).map(TaskItem.init).sorted(by: TaskItem.recentlyCompletedFirst)
            let recent = Array(items.prefix(Self.completedLimit))
            Task { @MainActor in
                guard let self, self.phase == .foreground else { return }
                self.completed = recent
            }
        }
    }

    /// Finds the next task due at a set time in the coming day and sleeps until then. One bounded
    /// query and one sleeping task, redone when reminders change.
    private func scheduleNextAlert() {
        nextAlert?.cancel()
        nextAlert = nil
        guard alertsInNotch, access == .granted, phase != .stopped else { return }
        let now = Date.now
        let store = eventStore.store
        let soon = store.predicateForIncompleteReminders(
            withDueDateStarting: now, ending: now.addingTimeInterval(86_400), calendars: chosenLists)
        store.fetchReminders(matching: soon) { @Sendable [weak self] reminders in
            let upcoming = (reminders ?? []).map(TaskItem.init)
                .filter { $0.hasTime && ($0.due ?? .distantPast) > Date.now }
                .min { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
            Task { @MainActor in
                guard let self else { return }
                self.arm(upcoming)
            }
        }
    }

    private func arm(_ task: TaskItem?) {
        nextAlert?.cancel()
        nextAlert = nil
        guard alertsInNotch, phase != .stopped else { return }
        // With nothing due in the coming day, look again once that day has passed.
        let wake = task?.due ?? .now.addingTimeInterval(86_400)
        nextAlert = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, wake.timeIntervalSinceNow))) } catch { return }
            if let task { self?.fire(task) } else { self?.scheduleNextAlert() }
        }
    }

    private func fire(_ task: TaskItem) {
        alerting = task
        onActivity?(Activity(feature: .tasks, symbol: "bell.fill", title: task.title, duration: .seconds(6)))
        scheduleNextAlert()
    }
}

extension TaskRepeat {
    var frequency: EKRecurrenceFrequency {
        switch self {
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        case .yearly: .yearly
        }
    }
}
