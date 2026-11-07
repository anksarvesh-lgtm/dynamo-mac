// SPDX-License-Identifier: MIT
import SwiftUI

// Per-feature settings, shown under each feature's toggle in the Settings window.

extension MediaFeature {
    public var settingsView: some View {
        @Bindable var media = self
        return Group {
            Toggle("Show track changes as a live activity", isOn: $media.announcesTracks)
            Toggle(isOn: $media.showsInClosedNotch) {
                Text("Show what's playing in the closed notch")
                Text("The cover and title stay beside the camera while music plays, and for a minute after it pauses.")
            }
            Toggle(isOn: $media.waveformFollowsAudio) {
                Text("Waveform follows the music")
                Text(
                    "Listens to your Mac's audio output while Media is open and playing. It's analyzed on this "
                        + "Mac as it plays and never recorded. macOS asks for permission the first time.")
            }
        }
    }
}

extension CalendarFeature {
    public var settingsView: some View {
        @Bindable var calendar = self
        return Group {
            AccessRow(access: calendar.access, pane: "Privacy_Calendars", request: calendar.requestAccess)
            Toggle("Show all-day events", isOn: $calendar.showsAllDay)
            Toggle(isOn: $calendar.showsTasks) {
                Text("Show tasks due today")
                Text("Lists open reminders due today or overdue under your events, once Tasks has access.")
            }
            Toggle(isOn: $calendar.countsDownToMeetings) {
                Text("Count down to meetings")
                Text(
                    "Five minutes before a meeting with a Zoom, Google Meet, Teams, Webex, Whereby, Jitsi, or "
                        + "FaceTime link, the closed notch counts down to it. Join from the Calendar tab.")
            }
        }
        .onAppear(perform: calendar.refreshAccess)
    }
}

extension TasksFeature {
    public var settingsView: some View {
        @Bindable var tasks = self
        return Group {
            AccessRow(access: tasks.access, pane: "Privacy_Reminders", request: tasks.requestAccess)
            Picker("List", selection: $tasks.listID) {
                Text("All lists").tag(String?.none)
                ForEach(tasks.lists) { list in
                    Text(list.title).tag(String?.some(list.id))
                }
            }
            .help("New tasks go to this list, or to your default list when showing all lists.")
            Toggle("Group by list instead of due date", isOn: $tasks.groupsByList)
            Toggle(isOn: $tasks.alertsAtDueTime) {
                Text("Alert at the due time")
                Text("New tasks with a time get an alert, which Reminders shows on your iPhone, iPad, and Mac.")
            }
            Toggle(isOn: $tasks.alertsInNotch) {
                Text("Show due tasks on the notch")
                Text("When a task's time comes, the notch shows it with Done and Snooze.")
            }
            Picker("Block time for", selection: $tasks.blockMinutes) {
                ForEach([15, 30, 45, 60, 90], id: \.self) { minutes in
                    Text("\(minutes) minutes").tag(minutes)
                }
            }
            .help("How long the Calendar event is when you block time for a task.")
        }
        .onAppear {
            tasks.refreshAccess()
            tasks.loadLists()
        }
    }
}

extension NotesFeature {
    public var settingsView: some View {
        NotesSettings(notes: self)
    }
}

private struct NotesSettings: View {
    @Bindable var notes: NotesFeature

    var body: some View {
        Group {
            LabeledContent {
                HStack {
                    Button("Choose\u{2026}", action: chooseFolder)
                    if notes.usesCustomFolder {
                        Button("Use Default") { notes.useDefaultFolder() }
                    }
                }
            } label: {
                Text("Folder: \(notes.usesCustomFolder ? notes.directory.lastPathComponent : "On this Mac")")
                Text(
                    "Pick a folder in iCloud Drive to reach your notes from the Files app or a Markdown app on "
                        + "iPhone. Notes on this Mac move to the new folder.")
            }
            Picker("Sort notes by", selection: $notes.sort) {
                ForEach(NoteSort.allCases) { sort in Text(sort.name).tag(sort) }
            }
            Toggle(isOn: $notes.quickNoteShortcut) {
                Text("Control-Option-N starts a new note")
                Text("Opens the notch on Notes from any app, ready to type.")
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        panel.message = "Choose where ILoveNotch keeps your notes."
        let iCloudDrive = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: iCloudDrive.path) { panel.directoryURL = iCloudDrive }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        notes.chooseFolder(url)
    }
}

/// EventKit access at a glance, with the next step when it isn't allowed.
private struct AccessRow: View {
    let access: EventAccess
    let pane: String
    let request: () -> Void

    var body: some View {
        LabeledContent("Access") {
            switch access {
            case .granted:
                Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .notDetermined:
                Button("Continue", action: request)  // App Review 5.1.1(iv): not "Allow"
            case .denied:
                Button("Open Privacy Settings") { NSWorkspace.shared.open(.privacySettings(pane)) }
            }
        }
    }
}

extension ShortcutsFeature {
    public var settingsView: some View {
        ShortcutsSettings(shortcuts: self)
    }
}

extension ClipboardFeature {
    public var settingsView: some View { ClipboardSettings(clipboard: self) }
}

private struct ClipboardSettings: View {
    let clipboard: ClipboardFeature

    var body: some View {
        Group {
            // A closure, not a method reference: see the app's GeneralSettings.
            Toggle(
                isOn: Binding(
                    get: { clipboard.isRecording },
                    set: { $0 ? clipboard.startRecording() : clipboard.stopRecording() })
            ) {
                Text("Keep a history of what you copy")
                Text(
                    "Looks at the clipboard twice a second while it's on. Skips passwords, anything marked private, "
                        + "and copies from password managers. Kept on this Mac only.")
            }
            if clipboard.isRecording, clipboard.access != .allowed {
                LabeledContent("Paste from other apps") {
                    Button("Open Privacy Settings") { NSWorkspace.shared.open(.privacySettings("Privacy_Pasteboard")) }
                }
            }
            LabeledContent(clipboard.items.count == 1 ? "1 item" : "\(clipboard.items.count) items") {
                Button("Clear History", role: .destructive, action: clipboard.clear)
                    .disabled(clipboard.items.allSatisfy(\.favorite))
            }
            .help("Favorites stay.")
        }
        .onAppear(perform: clipboard.refreshAccess)
    }
}

extension NetworkFeature {
    public var settingsView: some View { NetworkSettings(network: self) }
}

private struct NetworkSettings: View {
    @Bindable var network: NetworkFeature
    @State private var confirmsClear = false

    var body: some View {
        Group {
            Picker(selection: $network.closedNotch) {
                ForEach(NetworkFeature.ClosedNotch.allCases) { Text($0.title).tag($0) }
            } label: {
                Text("Show speed in the menu bar")
                Text(
                    "Beside the closed notch. While Downloading shows it once a download or upload runs at 1 MB/s or "
                        + "more for a few seconds, says how much it moved when it's done, and hides again; it checks "
                        + "every 3 seconds. Always reads the speed every second. Never shows nothing there, and reads "
                        + "the speed only while the tab is open.")
            }
            LabeledContent {
                Button("Clear History\u{2026}", role: .destructive) { confirmsClear = true }
                    .disabled(network.lifetime.total == 0)
            } label: {
                Text("History")
                Text(
                    "\(NetworkFeature.bytes(network.lifetime.down)) down and \(NetworkFeature.bytes(network.lifetime.up)) "
                        + "up, kept by the hour on this Mac. NetSpeed's history comes along the first time.")
            }
            .confirmationDialog("Clear the network history?", isPresented: $confirmsClear) {
                Button("Clear History", role: .destructive, action: network.clearHistory)
            } message: {
                Text("Every hour recorded so far is deleted. This can't be undone.")
            }
        }
        .onAppear(perform: network.refreshTotals)
    }
}

extension ShelfFeature {
    public var settingsView: some View {
        LabeledContent(items.count == 1 ? "1 item on the shelf" : "\(items.count) items on the shelf") {
            Button("Clear Shelf", role: .destructive, action: removeAll).disabled(items.isEmpty)
        }
    }
}

private struct ShortcutsSettings: View {
    @Bindable var shortcuts: ShortcutsFeature

    var body: some View {
        Group {
            if shortcuts.shortcuts.isEmpty {
                Text("Shortcuts you make in the Shortcuts app appear here.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(shortcuts.shortcuts, id: \.self) { name in
                    Toggle(
                        name,
                        isOn: Binding(
                            get: { !shortcuts.hidden.contains(name) },
                            set: { shown in
                                if shown { shortcuts.hidden.remove(name) } else { shortcuts.hidden.insert(name) }
                            }))
                }
            }
        }
        .onAppear(perform: shortcuts.refresh)
    }
}
