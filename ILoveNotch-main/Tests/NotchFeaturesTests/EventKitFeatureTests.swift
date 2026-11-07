// SPDX-License-Identifier: MIT
import EventKit
import Foundation
import NotchCore
import Testing

@testable import NotchFeatures

@MainActor
struct EventKitFeatureTests {
    private let defaults = UserDefaults(suiteName: "EventKitTests.\(UUID().uuidString)")!
    private let noon = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func theAgendaListsAllDayEventsFirstThenByTime() {
        let events = [
            DayEvent(id: "c", title: "Lunch", start: noon, end: noon + 3600),
            DayEvent(id: "a", title: "Holiday", start: noon - 43_200, end: noon + 43_200, isAllDay: true),
            DayEvent(id: "b", title: "Standup", start: noon - 7200, end: noon - 6300),
        ]
        #expect(events.sorted(by: DayEvent.agendaOrder).map(\.title) == ["Holiday", "Standup", "Lunch"])
    }

    @Test func tasksAreSoonestDueFirstAndUndatedLast() {
        let tasks = [
            TaskItem(id: "1", title: "someday"),
            TaskItem(id: "2", title: "tomorrow", due: noon + 86_400),
            TaskItem(id: "3", title: "overdue", due: noon - 86_400),
            TaskItem(id: "4", title: "Also someday"),
        ]
        #expect(tasks.sorted(by: TaskItem.order).map(\.title) == ["overdue", "tomorrow", "Also someday", "someday"])
    }

    @Test func completedTasksAreNewestFirst() {
        let done = [
            TaskItem(id: "1", title: "last week", completed: noon - 604_800),
            TaskItem(id: "2", title: "just now", completed: noon),
            TaskItem(id: "3", title: "yesterday", completed: noon - 86_400),
        ]
        let titles = done.sorted(by: TaskItem.recentlyCompletedFirst).map(\.title)
        #expect(titles == ["just now", "yesterday", "last week"])
    }

    @Test func theCompletedSectionRemembersWhetherItIsOpen() {
        let store = EventStore()
        TasksFeature(eventStore: store, defaults: defaults).showsCompleted = true
        #expect(TasksFeature(eventStore: store, defaults: defaults).showsCompleted)
    }

    @Test func withoutAccessNothingIsReadOrWatched() {
        // Test runners never grant EventKit access, so this is the not-yet-allowed path.
        let store = EventStore()
        let calendar = CalendarFeature(eventStore: store, defaults: defaults)
        let tasks = TasksFeature(eventStore: store, defaults: defaults)
        for feature in [calendar, tasks] as [any NotchFeature] {
            feature.phase = .foreground
        }
        #expect(calendar.access != .granted && calendar.events.isEmpty && !calendar.isObserving)
        #expect(tasks.access != .granted && tasks.tasks.isEmpty && !tasks.isObserving)
    }

    @Test func onlyYourOwnEventsCanBeChangedFromTheNotch() {
        let store = EventStore().store
        let event = EKEvent(eventStore: store)
        event.title = "Lunch"
        event.startDate = noon
        event.endDate = noon + 3600
        #expect(DayEvent(event).id == DayEvent.id(for: event), "a change finds the event by the agenda's id")
        #expect(!DayEvent(event).isEditable, "no calendar to change it in")
        event.calendar = EKCalendar(for: .event, eventStore: store)
        #expect(DayEvent(event).isEditable, "yours, with nobody invited")

        // Without access, nothing is changed or deleted, and nothing breaks.
        let calendar = CalendarFeature(eventStore: EventStore(), defaults: defaults)
        let lunch = DayEvent(id: "x", title: "Lunch", start: noon, end: noon + 3600)
        #expect(!calendar.update(lunch, title: "Brunch", start: noon, end: noon + 3600))
        calendar.delete(lunch)
        #expect(calendar.notice == nil)
    }

    @Test func settingsPersist() {
        let store = EventStore()
        CalendarFeature(eventStore: store, defaults: defaults).showsAllDay = false
        CalendarFeature(eventStore: store, defaults: defaults).showsTasks = false
        let tasks = TasksFeature(eventStore: store, defaults: defaults)
        #expect(tasks.alertsInNotch && tasks.alertsAtDueTime && tasks.blockMinutes == 30, "defaults")
        tasks.listID = "work"
        tasks.groupsByList = true
        tasks.alertsInNotch = false
        tasks.blockMinutes = 45
        #expect(!CalendarFeature(eventStore: store, defaults: defaults).showsAllDay)
        #expect(!CalendarFeature(eventStore: store, defaults: defaults).showsTasks)
        let relaunched = TasksFeature(eventStore: store, defaults: defaults)
        #expect(relaunched.listID == "work" && relaunched.groupsByList)
        #expect(!relaunched.alertsInNotch && relaunched.blockMinutes == 45)
    }

    @Test func quickAddReadsPriorityListAndRepeats() {
        let draft = TaskDraft.parse("Water plants !! #Home every week")
        #expect(draft.title == "Water plants")
        #expect(draft.priority == .medium)
        #expect(draft.list == "Home")
        #expect(draft.repeats == .weekly)
        #expect(draft.due != nil, "a repeating task starts today")

        let plain = TaskDraft.parse("Buy milk")
        #expect(plain.title == "Buy milk" && !plain.hasDetails)
        #expect(TaskDraft.parse("!!!").title == "!!!", "a line of only marks stays the title")
    }

    @Test func quickAddReadsDatesAndTimes() throws {
        let draft = TaskDraft.parse("Call mom tomorrow at 5pm !!!")
        let due = try #require(draft.due)
        #expect(draft.title == "Call mom")
        #expect(draft.priority == .high)
        #expect(draft.hasTime)
        #expect(Calendar.current.isDateInTomorrow(due))
        #expect(Calendar.current.component(.hour, from: due) == 17)
    }

    @Test func eventsAreReadFromPlainWords() throws {
        let draft = try #require(EventDraft.parse("Lunch with Sam tomorrow 1pm for 90 min"))
        #expect(draft.title == "Lunch with Sam")
        #expect(!draft.isAllDay)
        #expect(draft.duration == 90 * 60)
        #expect(Calendar.current.isDateInTomorrow(draft.start))
        #expect(EventDraft.parse("Lunch with Sam") == nil, "an event needs a time")
    }

    @Test func tasksGroupByWhenTheyAreDue() throws {
        let calendar = Calendar.current
        let now = try #require(calendar.date(bySettingHour: 12, minute: 0, second: 0, of: noon))
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
        #expect(TaskGroup(due: nil, hasTime: false, now: now) == .someday)
        #expect(TaskGroup(due: day(-1), hasTime: false, now: now) == .overdue)
        #expect(TaskGroup(due: today, hasTime: false, now: now) == .today, "a day's task isn't late until it ends")
        #expect(TaskGroup(due: now - 60, hasTime: true, now: now) == .overdue, "a timed task is late once it passes")
        #expect(TaskGroup(due: day(1), hasTime: false, now: now) == .tomorrow)
        #expect(TaskGroup(due: day(3), hasTime: false, now: now) == .thisWeek)
        #expect(TaskGroup(due: day(30), hasTime: false, now: now) == .later)
    }

    @Test func sectionsFollowTheChosenGrouping() throws {
        let tasks = TasksFeature(eventStore: EventStore(), defaults: defaults)
        let now = Date.now
        tasks.show(
            tasks: [
                TaskItem(id: "1", title: "late", due: now - 86_400 * 2, listTitle: "Work"),
                TaskItem(id: "2", title: "someday", listTitle: "Home"),
            ],
            completed: [])
        #expect(tasks.sections(now: now).map(\.title) == ["Overdue", "No Date"])
        #expect(tasks.sections(now: now).first?.isOverdue == true)
        tasks.groupsByList = true
        #expect(Set(tasks.sections(now: now).map(\.title)) == ["Work", "Home"])
    }

    @Test func draggedTasksKeepTheirPlaceInTheirSection() {
        let tasks = TasksFeature(eventStore: EventStore(), defaults: defaults)
        let late = TaskItem(id: "l", title: "late", due: .now - 86_400 * 2)
        let a = TaskItem(id: "a", title: "Alpha")
        let b = TaskItem(id: "b", title: "Bravo")
        let c = TaskItem(id: "c", title: "Charlie")
        tasks.show(tasks: [late, a, b, c], completed: [])
        func undated() -> [String] { tasks.sections().last?.tasks.map(\.id) ?? [] }
        tasks.move(c, to: a)
        #expect(undated() == ["c", "a", "b"], "dragged up: lands where the target was")
        tasks.move(c, to: b)
        #expect(undated() == ["a", "b", "c"], "dragged down: lands after the target")
        tasks.move(late, to: a)
        #expect(tasks.sections().first?.tasks.map(\.id) == ["l"], "another section's task stays put")
        tasks.show(tasks: [late, TaskItem(id: "d", title: "Aardvark"), a, b, c], completed: [])
        #expect(undated() == ["a", "b", "c", "d"], "a new task joins the end, as in Reminders")
        #expect(TasksFeature(eventStore: EventStore(), defaults: defaults).manualOrder == ["a", "b", "c"])
    }

    @Test func prioritiesMapToRemindersValues() {
        for priority in TaskPriority.allCases {
            #expect(TaskPriority(eventKit: priority.eventKitValue) == priority)
        }
        #expect(TaskPriority(eventKit: 3) == .high)
        #expect(TaskPriority(eventKit: 7) == .low)
        #expect(TaskPriority.high.marks == "!!!")
    }

    @Test func listNamesMatchLooselyAndBlocksStartOnTheQuarterHour() {
        #expect(TasksFeature.listName("Work Stuff", matches: "workstuff"))
        #expect(!TasksFeature.listName("Work", matches: "Home"))
        let quarterHour = Date(timeIntervalSinceReferenceDate: 811_692_000)
        let start = TaskItem.blockStart(for: TaskItem(id: "1", title: "t"), now: quarterHour + 7 * 60)
        #expect(start == quarterHour + 15 * 60)
        let ahead = TaskItem(id: "2", title: "t", due: noon + 7200, hasTime: true)
        #expect(TaskItem.blockStart(for: ahead, now: noon) == noon + 7200, "a due time still ahead is kept")
    }

    @Test func dueLabelsAreShortAndRelative() throws {
        let calendar = Calendar.current
        let now = try #require(calendar.date(bySettingHour: 12, minute: 0, second: 0, of: noon))
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)))
        #expect(DueLabel.text(for: calendar.startOfDay(for: now), hasTime: false, now: now) == "Today")
        #expect(DueLabel.text(for: tomorrow, hasTime: false, now: now) == "Tomorrow")
        #expect(DueLabel.text(for: tomorrow + 3600 * 9, hasTime: true, now: now).hasPrefix("Tomorrow "))
    }
}
