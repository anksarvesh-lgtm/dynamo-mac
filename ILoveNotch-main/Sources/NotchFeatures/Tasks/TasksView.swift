// SPDX-License-Identifier: MIT
import SwiftUI

/// The tasks tab: open reminders under date or list headings, a collapsible section of recently
/// completed ones, and a quick-add field that reads dates, priorities, and lists as you type.
/// Hovering a task shows its actions; double-clicking its title renames it; dragging it onto another
/// in its section moves it there. Typing in a field gives the notch keyboard focus.
struct TasksView: View {
    let tasks: TasksFeature
    @State private var draft = ""
    /// Tasks just ticked: they show a checkmark for a beat before moving to Completed.
    @State private var ticking: Set<TaskItem.ID> = []
    /// The task being dragged to a new place, and the one it's over.
    @State private var dragging: TaskItem?
    @State private var dropTarget: TaskItem.ID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if tasks.access != .granted {
            EventAccessView(
                access: tasks.access, symbol: "checklist", what: "reminders", settingsPane: "Privacy_Reminders",
                request: tasks.requestAccess)
        } else {
            VStack(spacing: 5) {
                // A due task's banner stands in for the summary, which keeps the list in view in the
                // smallest notch.
                if let task = tasks.alerting { alertBanner(task) } else { header }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        if tasks.tasks.isEmpty {
                            Label("All done", systemImage: "checkmark.circle")
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.6))
                                .padding(.vertical, 6)
                        }
                        ForEach(tasks.sections()) { section in
                            sectionHeader(section)
                            ForEach(section.tasks) { task in
                                TaskRow(
                                    tasks: tasks, task: task, ticked: ticking.contains(task.id),
                                    showsList: !tasks.groupsByList && tasks.listID == nil && tasks.lists.count > 1,
                                    tick: { tick(task) }
                                )
                                .overlay(alignment: draggedFromAbove(task, in: section) ? .bottom : .top) {
                                    if dropTarget == task.id {
                                        Capsule().fill(Color.accentColor).frame(height: 2).padding(.horizontal, 4)
                                    }
                                }
                                .onDrag {
                                    dragging = task
                                    return NSItemProvider(object: task.title as NSString)
                                }
                                .dropDestination(for: String.self) { items, _ in
                                    drop(items.first, on: task, in: section)
                                } isTargeted: { over in
                                    if over, section.tasks.contains(where: { $0.id == dragging?.id }) {
                                        dropTarget = task.id
                                    } else if dropTarget == task.id {
                                        dropTarget = nil
                                    }
                                }
                                .accessibilityAction(named: "Move Up") { step(task, by: -1, in: section) }
                                .accessibilityAction(named: "Move Down") { step(task, by: 1, in: section) }
                            }
                        }
                        if !tasks.completed.isEmpty { completedSection }
                    }
                    .padding(.vertical, 4)
                }
                .fadingEdges()
                quickAdd
            }
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: tasks.alerting)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            if let notice = tasks.notice {
                Label(notice, systemImage: "checkmark.circle")
                    .foregroundStyle(.white.opacity(0.8))
                    .transition(.opacity)
            } else {
                Text(summary).foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) {
                    tasks.groupsByList.toggle()
                }
            } label: {
                Label(
                    tasks.groupsByList ? "By List" : "By Date",
                    systemImage: tasks.groupsByList ? "list.bullet" : "calendar")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.7))
            .help(tasks.groupsByList ? "Group by due date" : "Group by list")
        }
        .font(.caption.weight(.medium))
        .lineLimit(1)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: tasks.notice)
    }

    /// "2 overdue · 3 today", or how many are open.
    private var summary: String {
        let now = Date.now
        let overdue = tasks.tasks.filter { $0.isOverdue(now: now) }.count
        let today = tasks.tasks.filter { $0.group(now: now) == .today }.count
        var parts: [String] = []
        if overdue > 0 { parts.append("\(overdue) overdue") }
        if today > 0 { parts.append("\(today) today") }
        if parts.isEmpty { return tasks.tasks.count == 1 ? "1 open task" : "\(tasks.tasks.count) open tasks" }
        return parts.joined(separator: " · ")
    }

    private func sectionHeader(_ section: TaskSection) -> some View {
        HStack(spacing: 5) {
            if let color = section.color {
                Circle().fill(color.color).frame(width: 6, height: 6)
            }
            Text(section.title)
            Text("\(section.tasks.count)").foregroundStyle(.white.opacity(0.4))
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(section.isOverdue ? Color.red : .white.opacity(0.6))
        .padding(.top, 6)
        .padding(.bottom, 1)
        .padding(.horizontal, 4)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Due alert

    private func alertBanner(_ task: TaskItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.fill")
                .foregroundStyle(.yellow)
                .symbolEffect(.bounce, value: task.id)
            VStack(alignment: .leading, spacing: 0) {
                Text("Due now").font(.caption2).foregroundStyle(.white.opacity(0.6))
                Text(task.title).font(.callout.weight(.semibold)).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button("Done") { tick(task) }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.white.opacity(0.18), in: Capsule())
            Button("Snooze \(TasksFeature.snoozeMinutes) min") { tasks.snooze(task) }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.white.opacity(0.1), in: Capsule())
            Button {
                tasks.dismissAlert()
            } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .accessibilityLabel("Dismiss")
        }
        .buttonStyle(.plain)
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.yellow.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: Quick add

    private var quickAdd: some View {
        let parsed: TaskDraft? = draft.trimmingCharacters(in: .whitespaces).isEmpty ? nil : TaskDraft.parse(draft)
        return VStack(alignment: .leading, spacing: 3) {
            if let parsed, parsed.hasDetails {
                DraftChips(draft: parsed)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            TextField("New task: try \u{201C}Pay rent fri 9am !! #Home\u{201D}", text: $draft)
                .textFieldStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                .onSubmit {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) {
                        _ = tasks.add(draft)
                    }
                    draft = ""
                }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: parsed?.hasDetails ?? false)
    }

    // MARK: Completed

    private var completedSection: some View {
        Group {
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
                    tasks.showsCompleted.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(tasks.showsCompleted ? 90 : 0))
                    Text("Completed")
                    Text("\(tasks.completed.count)").foregroundStyle(.white.opacity(0.45))
                    Spacer(minLength: 0)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.top, 10)
                .padding(.bottom, 4)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Completed, \(tasks.completed.count) tasks")
            .accessibilityValue(tasks.showsCompleted ? "Expanded" : "Collapsed")
            if tasks.showsCompleted {
                ForEach(tasks.completed) { task in completedRow(task) }
            }
        }
    }

    private func completedRow(_ task: TaskItem) -> some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) { tasks.reopen(task) }
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle((task.color?.color ?? .white).opacity(0.6))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reopen \(task.title)")
            VStack(alignment: .leading, spacing: 1) {
                Text(task.title).font(.callout).strikethrough().lineLimit(1)
                if let done = task.completed, done != .distantPast {
                    Text(done, format: .relative(presentation: .named)).font(.caption)
                }
            }
            .foregroundStyle(.white.opacity(0.45))
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .contextMenu {
            Button("Delete", role: .destructive) { tasks.delete(task) }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: Reordering

    /// The dragged task comes from above `task`, so it would land below it.
    private func draggedFromAbove(_ task: TaskItem, in section: TaskSection) -> Bool {
        let ids = section.tasks.map(\.id)
        guard let from = dragging.flatMap({ ids.firstIndex(of: $0.id) }) else { return false }
        return from < (ids.firstIndex(of: task.id) ?? 0)
    }

    /// Drops the dragged task where `target` is. The text must be the dragged task's title, so a drag
    /// that ended somewhere else can't move it on a later drop.
    private func drop(_ text: String?, on target: TaskItem, in section: TaskSection) -> Bool {
        defer {
            dragging = nil
            dropTarget = nil
        }
        guard let moving = dragging, text == moving.title, section.tasks.contains(where: { $0.id == moving.id })
        else { return false }
        reorder(moving, to: target)
        return true
    }

    /// One place up or down, for VoiceOver.
    private func step(_ task: TaskItem, by offset: Int, in section: TaskSection) {
        guard let index = section.tasks.firstIndex(where: { $0.id == task.id }),
            section.tasks.indices.contains(index + offset)
        else { return }
        reorder(task, to: section.tasks[index + offset])
    }

    private func reorder(_ task: TaskItem, to target: TaskItem) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) {
            tasks.move(task, to: target)
        }
    }

    /// Shows the checkmark for a beat, then moves the task to Completed.
    private func tick(_ task: TaskItem) {
        ticking.insert(task.id)
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 350))
            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.82)) {
                tasks.complete(task)
            }
            ticking.remove(task.id)
        }
    }
}

/// One open task. Hovering it lights the row and shows its actions; double-clicking the title edits it.
private struct TaskRow: View {
    let tasks: TasksFeature
    let task: TaskItem
    let ticked: Bool
    /// Show the task's list under it, for date groups that mix lists.
    let showsList: Bool
    let tick: () -> Void

    @State private var hovering = false
    @State private var editing = false
    @State private var title = ""
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Button(action: tick) {
                Image(systemName: ticked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(task.color?.color ?? .white)
                    .symbolEffect(.bounce, value: ticked)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(task.title)")
            VStack(alignment: .leading, spacing: 1) {
                if editing {
                    TextField("Task", text: $title)
                        .textFieldStyle(.plain)
                        .font(.callout)
                        .focused($focused)
                        .takesKeyboard(editing)
                        .onSubmit(commitRename)
                        .onChange(of: focused) { _, isFocused in
                            if !isFocused { commitRename() }
                        }
                } else {
                    HStack(spacing: 4) {
                        if task.priority != .none {
                            Text(task.priority.marks).fontWeight(.heavy).foregroundStyle(.orange)
                        }
                        Text(task.title).lineLimit(1)
                    }
                    .font(.callout)
                    .opacity(ticked ? 0.5 : 1)
                    .onTapGesture(count: 2, perform: beginRename)
                }
                details
            }
            Spacer(minLength: 0)
            if hovering, !editing {
                actions.transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(hovering ? Color.white.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onHover { inside in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { hovering = inside }
        }
        .contextMenu { menuItems }
        .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .move(edge: .bottom))))
        .accessibilityAction(named: "Rename", beginRename)
        .accessibilityAction(named: "Block Time in Calendar") { tasks.blockTime(for: task) }
    }

    /// Due date, repeat, alert, and list, when there are any.
    @ViewBuilder private var details: some View {
        let list = showsList ? task.listTitle : nil
        if task.due != nil || task.repeats || list != nil {
            HStack(spacing: 5) {
                if let due = task.due {
                    Text(DueLabel.text(for: due, hasTime: task.hasTime))
                        .foregroundStyle(task.isOverdue() ? Color.red : .white.opacity(0.55))
                }
                if task.repeats { Image(systemName: "repeat") }
                if task.hasAlert, task.hasTime { Image(systemName: "bell") }
                if let list { Text(list).foregroundStyle((task.color?.color ?? .white).opacity(0.8)) }
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.55))
            .lineLimit(1)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                tasks.blockTime(for: task)
            } label: {
                Image(systemName: "calendar.badge.plus")
            }
            .help("Block \(tasks.blockMinutes) min in Calendar")
            .accessibilityLabel("Block time in Calendar")
            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .foregroundStyle(.white.opacity(0.75))
    }

    @ViewBuilder private var menuItems: some View {
        Button("Rename", action: beginRename)
        Menu("Due") {
            ForEach(DueChoice.allCases) { choice in
                Button(choice.name) { tasks.setDue(task, to: choice) }
            }
        }
        Picker(
            "Priority",
            selection: Binding(get: { task.priority }, set: { tasks.setPriority(task, to: $0) })
        ) {
            ForEach(TaskPriority.allCases, id: \.self) { priority in
                Text(priority == .none ? "None" : "\(priority.name) \(priority.marks)").tag(priority)
            }
        }
        .pickerStyle(.menu)
        if tasks.lists.count > 1 {
            Picker(
                "List",
                selection: Binding(get: { task.listID ?? "" }, set: { tasks.move(task, toList: $0) })
            ) {
                ForEach(tasks.lists) { list in
                    Text(list.title).tag(list.id)
                }
            }
            .pickerStyle(.menu)
        }
        Button("Block \(tasks.blockMinutes) Min in Calendar") { tasks.blockTime(for: task) }
        Divider()
        Button("Delete", role: .destructive) { tasks.delete(task) }
    }

    private func beginRename() {
        title = task.title
        editing = true
        Task { @MainActor in focused = true }  // once the field is on screen
    }

    private func commitRename() {
        guard editing else { return }
        editing = false
        tasks.rename(task, to: title)
    }
}

/// What quick add has understood so far, as small chips above the field.
private struct DraftChips: View {
    let draft: TaskDraft

    var body: some View {
        HStack(spacing: 4) {
            if let due = draft.due {
                chip(DueLabel.text(for: due, hasTime: draft.hasTime), symbol: "calendar")
            }
            if let repeats = draft.repeats { chip(repeats.name, symbol: "repeat") }
            if draft.priority != .none { chip(draft.priority.name, symbol: "exclamationmark") }
            if let list = draft.list { chip(list, symbol: "list.bullet") }
            Spacer(minLength: 0)
        }
        .font(.caption2.weight(.medium))
        .accessibilityElement(children: .combine)
    }

    private func chip(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.white.opacity(0.12), in: Capsule())
    }
}
