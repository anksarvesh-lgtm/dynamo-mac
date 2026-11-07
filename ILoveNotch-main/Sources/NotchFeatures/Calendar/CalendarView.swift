// SPDX-License-Identifier: MIT
import SwiftUI

/// The calendar tab: today's agenda, with past events dimmed and a Join button on events with a
/// video call that hasn't ended, the tasks due today beneath it, and a field that adds an event
/// from a line like "Lunch with Sam tomorrow 1pm". Your own events can be edited in place or
/// deleted from the notch.
struct CalendarView: View {
    let calendar: CalendarFeature
    @State private var draft = ""
    /// The event being edited in place.
    @State private var editing: DayEvent.ID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(calendar: CalendarFeature, editing: DayEvent.ID? = nil) {
        self.calendar = calendar
        _editing = State(initialValue: editing)
    }

    private var spring: Animation? { reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85) }

    var body: some View {
        if calendar.access != .granted {
            EventAccessView(
                access: calendar.access, symbol: "calendar", what: "calendars", settingsPane: "Privacy_Calendars",
                request: calendar.requestAccess)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Button(action: calendar.openCalendarApp) {
                        Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    }
                    .buttonStyle(.plain)
                    .help("Open Calendar")
                    Spacer(minLength: 0)
                    if let notice = calendar.notice {
                        Text(notice).lineLimit(1).transition(.opacity)
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: calendar.notice)
                if calendar.events.isEmpty, calendar.dueTasks.isEmpty {
                    FeatureUnavailableView(symbol: "calendar", title: "Nothing today", message: "Enjoy the free time.")
                } else {
                    agenda
                }
                // Steps aside while an event is edited, which gives the editor room in the smallest notch.
                if editing == nil {
                    TextField("New event: try \u{201C}Lunch tomorrow 1pm for 1h\u{201D}", text: $draft)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                        .onSubmit {
                            // Text without a time stays in the field so it can be finished.
                            if calendar.addEvent(draft) { draft = "" }
                        }
                }
            }
        }
    }

    /// The events, one of them perhaps open for editing, then the tasks due today.
    private var agenda: some View {
        ScrollViewReader { list in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(calendar.events) { event in eventRow(event) }
                    if !calendar.dueTasks.isEmpty {
                        Text("Tasks")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.top, calendar.events.isEmpty ? 0 : 6)
                            .padding(.horizontal, 4)  // in line with the events
                            .accessibilityAddTraits(.isHeader)
                        ForEach(calendar.dueTasks) { task in taskRow(task) }
                    }
                }
                .padding(.vertical, 6)
            }
            .fadingEdges()
            // In a small notch the editor can open below the fold.
            .onChange(of: editing) { _, id in
                guard let id else { return }
                withAnimation(spring) { list.scrollTo(id) }
            }
        }
    }

    @ViewBuilder private func eventRow(_ event: DayEvent) -> some View {
        if editing == event.id {
            EventEditor(event: event) { title, start, end in
                if calendar.update(event, title: title, start: start, end: end) {
                    withAnimation(spring) { editing = nil }
                }
            } cancel: {
                withAnimation(spring) { editing = nil }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
        } else {
            EventRow(calendar: calendar, event: event) {
                withAnimation(spring) { editing = event.id }
            }
            .transition(.opacity)
        }
    }

    private func taskRow(_ task: TaskItem) -> some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.82)) {
                    calendar.complete(task)
                }
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(task.color?.color ?? .white)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(task.title)")
            Text(task.title).font(.callout).lineLimit(1)
            Spacer(minLength: 0)
            if let due = task.due {
                Text(DueLabel.text(for: due, hasTime: task.hasTime))
                    .font(.caption)
                    .foregroundStyle(task.isOverdue() ? Color.red : .white.opacity(0.55))
            }
        }
        .padding(.horizontal, 4)
        .transition(.opacity)
    }
}

/// One event: its calendar's color, its title, and when. Hovering one of your own events lights it
/// and shows Edit and Delete; Delete asks for a second click before it deletes. Double-clicking or
/// the context menu edits it too.
private struct EventRow: View {
    let calendar: CalendarFeature
    let event: DayEvent
    let edit: () -> Void

    @State private var hovering = false
    /// Delete was clicked once: the next click deletes.
    @State private var confirming = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let past = !event.isAllDay && event.end < .now
        let joinable = event.meeting != nil && !past && !event.isDeclined
        HStack(spacing: 8) {
            Capsule()
                .fill(event.color?.color ?? .white)
                .frame(width: 3, height: 26)
                .opacity(past && !hovering ? 0.45 : 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(.callout.weight(.medium)).lineLimit(1)
                Group {
                    if event.isAllDay {
                        Text("All day")
                    } else {
                        Text(event.start, format: .dateTime.hour().minute()) + Text(" – ")
                            + Text(event.end, format: .dateTime.hour().minute())
                    }
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
            }
            .opacity(past && !hovering ? 0.45 : 1)
            Spacer(minLength: 0)
            if hovering, event.isEditable {
                actions.transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
            }
            if joinable, let meeting = event.meeting {
                joinButton(meeting)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(hovering ? Color.white.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onHover { inside in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                hovering = inside
                if !inside { confirming = false }
            }
        }
        .onTapGesture(count: 2) { if event.isEditable { edit() } }
        .contextMenu {
            if event.isEditable { Button("Edit", action: edit) }
            if let meeting = event.meeting {
                Button("Join \(meeting.service)") { calendar.join(event) }.disabled(!joinable)
                Button("Copy Link") { calendar.copyLink(event) }
            }
            if event.isEditable {
                Divider()
                Button("Delete Event", role: .destructive) { calendar.delete(event) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityActions {
            if joinable { Button("Join") { calendar.join(event) } }
            if event.isEditable {
                Button("Edit", action: edit)
                Button("Delete") { calendar.delete(event) }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: edit) {
                Image(systemName: "pencil").contentShape(Rectangle())
            }
            .help("Edit")
            .accessibilityLabel("Edit")
            Button {
                if confirming {
                    calendar.delete(event)
                } else {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8)) {
                        confirming = true
                    }
                }
            } label: {
                if confirming {
                    Text("Delete")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.red.opacity(0.85), in: Capsule())
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .trailing)))
                } else {
                    Image(systemName: "trash").contentShape(Rectangle())
                }
            }
            .help(confirming ? "Click again to delete" : "Delete")
            .accessibilityLabel("Delete")
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .foregroundStyle(.white.opacity(0.8))
    }

    /// Stands out while the meeting's countdown is on.
    private func joinButton(_ meeting: MeetingLink) -> some View {
        let soon = calendar.countingDown?.id == event.id
        return Button {
            calendar.join(event)
        } label: {
            Label("Join", systemImage: "video.fill")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(soon ? Color.green.opacity(0.85) : .white.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Join on \(meeting.service). Right-click to copy the link.")
    }
}

/// An event being changed in place: its title, and when it starts and ends (an all-day event keeps
/// its days). Moving the start keeps the length. Return or Save saves; Cancel leaves it as it was.
private struct EventEditor: View {
    let event: DayEvent
    let save: (_ title: String, _ start: Date, _ end: Date) -> Void
    let cancel: () -> Void

    @State private var title: String
    @State private var start: Date
    @State private var end: Date
    @FocusState private var focused: Bool

    init(
        event: DayEvent, save: @escaping (_ title: String, _ start: Date, _ end: Date) -> Void,
        cancel: @escaping () -> Void
    ) {
        self.event = event
        self.save = save
        self.cancel = cancel
        _title = State(initialValue: event.title)
        _start = State(initialValue: event.start)
        _end = State(initialValue: event.end)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && (event.isAllDay || end > start)
    }

    /// Two lines, so it fits even the smallest notch (with the new-event field out of the way): the
    /// title with Cancel and Save, then the times.
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(event.color?.color ?? .white)
                    .frame(width: 3, height: 18)
                TextField("Title", text: $title)
                    .textFieldStyle(.plain)
                    .font(.callout.weight(.medium))
                    .focused($focused)
                    .takesKeyboard(true)
                    .onSubmit { if canSave { save(title, start, end) } }
                buttons
            }
            HStack(spacing: 6) { when }
                .padding(.leading, 11)  // under the title, past the color bar
                .datePickerStyle(.field)
                .labelsHidden()
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.plain)
        .padding(.leading, 4)  // the color bar stays where the row had it
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
        .onChange(of: start) { old, new in end += new.timeIntervalSince(old) }
        .onAppear { Task { @MainActor in focused = true } }
    }

    @ViewBuilder private var when: some View {
        if event.isAllDay {
            Text("All day").font(.caption).foregroundStyle(.white.opacity(0.55))
        } else {
            DatePicker("Starts", selection: $start, displayedComponents: [.date, .hourAndMinute])
            Text("–").foregroundStyle(.white.opacity(0.55))
            DatePicker("Ends", selection: $end, displayedComponents: .hourAndMinute)
        }
    }

    @ViewBuilder private var buttons: some View {
        Button("Cancel", action: cancel)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(.white.opacity(0.1), in: Capsule())
        Button("Save") { save(title, start, end) }
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(.white.opacity(canSave ? 0.25 : 0.08), in: Capsule())
            .disabled(!canSave)
    }
}
