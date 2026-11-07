import SwiftUI

/// The notification-shade content, drawn directly on the island's black surface: a grabber, the
/// clock, quick toggles, timer, next event, Now Playing, shelf, clipboard, then app-grouped
/// notifications.
struct ShadeContent: View {
    @ObservedObject var state: IslandState
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var updater = Updater.shared
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var clipboard: ClipboardHistory
    @ObservedObject var calendar: CalendarModule
    @State private var now = Date()
    @State private var copied: String?
    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    init(state: IslandState) {
        self.state = state
        self.shelf = state.shelf
        self.clipboard = state.clipboard
        self.calendar = state.calendar
    }

    var body: some View {
        VStack(spacing: 12) {
            grabber
            header
            ScrollView {
                VStack(spacing: UI.stack) {
                    if settings.quickTogglesEnabled { QuickTogglesRow(state: state) }
                    if state.showMirror {
                        CameraMirrorView()
                            .frame(height: 190)
                            .clipShape(RoundedRectangle(cornerRadius: UI.cardRadius, style: .continuous))
                            .transition(.opacity)
                    }
                    if settings.timerEnabled { TimerCard(engine: state.timer) }
                    if settings.calendarEnabled { CalendarRow(calendar: calendar) }
                    if let media = state.media {
                        ShadeMediaCard(media: media, controller: state.mediaController)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    if settings.shelfEnabled, !shelf.items.isEmpty { ShelfStrip(shelf: shelf) }
                    if settings.clipboardEnabled, !clipboard.items.isEmpty { clipboardSection }
                    if state.hasNotifications {
                        ForEach(state.groups) { group in
                            NotificationGroupCard(group: group, state: state)
                        }
                    } else if state.media == nil, !state.showMirror {
                        empty
                    }
                }
                .padding(.bottom, 2)
            }
            .frame(maxHeight: 620)
            .scrollIndicators(.never)
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white)
        .onReceive(clock) { now = $0 }
    }

    private var grabber: some View {
        Capsule()
            .fill(.white.opacity(0.28))
            .frame(width: 36, height: 5)
            .contentShape(Rectangle().inset(by: -10))
            .onTapGesture { state.closeShade() }
    }

    /// Clock + date on the left (like a phone's shade), actions on the right.
    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(now, format: .dateTime.hour().minute())
                    .font(UI.numeral(22)).monospacedDigit()
                Text(now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(UI.body(10.5)).foregroundStyle(.secondary)
            }
            Spacer()
            IconButton(symbol: "magnifyingglass", help: "Search (\(settings.hotkeyDescription))") {
                state.openLauncherFromShade()
            }
            IconButton(symbol: "gearshape.fill", help: "Settings") { SettingsWindowController.shared.show() }
            if let release = updater.available {
                PillButton(title: "Update", symbol: "arrow.down.circle.fill", prominent: true,
                           help: "NotchIsland \(release.version) is available: see what's new and update") {
                    SettingsWindowController.shared.show(tab: "updates")
                }
            }
            if state.hasNotifications {
                PillButton(title: "Clear All") { state.clearAll() }
            }
        }
        .padding(.horizontal, 4)
    }

    private var clipboardSection: some View {
        let items = state.showAllClipboard ? clipboard.items : Array(clipboard.items.prefix(5))
        return VStack(alignment: .leading, spacing: 0) {
            Eyebrow(symbol: "doc.on.clipboard.fill", "Clipboard", count: clipboard.items.count) {
                if clipboard.items.count > 5 {
                    PillButton(title: state.showAllClipboard ? "Less" : "All \(clipboard.items.count)", small: true) {
                        withAnimation(Motion.quick) { state.showAllClipboard.toggle() }
                    }
                }
                IconButton(symbol: "xmark", size: 22, help: "Clear clipboard history") { clipboard.clear() }
            }
            .padding(.bottom, 6)
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { HairlineDivider() }
                HStack(alignment: .top, spacing: 8) {
                    Text(item.text)
                        .font(UI.body(11))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if copied == item.text {
                        Label("Copied", systemImage: "checkmark")
                            .font(UI.caption()).foregroundStyle(Theme.accent)
                            .transition(.opacity)
                    } else {
                        Text(NotificationBannerView.relative(item.date))
                            .font(UI.caption()).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 7)
                .contentShape(Rectangle())
                .onTapGesture {
                    clipboard.copy(item)
                    withAnimation(Motion.quick) { copied = item.text }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation(Motion.quick) { if copied == item.text { copied = nil } }
                    }
                }
                .help("Click to copy")
            }
        }
        .islandCard()
    }

    private var empty: some View {
        VStack(spacing: 8) {
            IconBadge(symbol: "bell.slash.fill", size: 44)
            Text("No notifications").font(UI.title(12.5))
            Text("You're all caught up").font(UI.body(10.5)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}

// MARK: - Quick toggles

/// Five equal tiles: Dark Mode, Keep Awake, Wi-Fi, Mirror, Focus. Focus reflects the system's
/// Focus mode (lit with its name while one is on) and opens Focus settings, since macOS has no
/// public API to switch it.
struct QuickTogglesRow: View {
    @ObservedObject var state: IslandState
    @ObservedObject private var caffeine = Caffeine.shared
    @ObservedObject private var status: SystemStatus
    @State private var dark = QuickSystem.isDarkMode
    @State private var wifi: Bool?

    init(state: IslandState) {
        self.state = state
        self.status = state.status
    }

    var body: some View {
        HStack(spacing: 8) {
            ToggleTile(symbol: "circle.lefthalf.filled", label: "Dark Mode", on: dark, help: "Toggle dark mode") {
                dark.toggle()
                QuickSystem.toggleDarkMode()
            }
            ToggleTile(symbol: "cup.and.saucer.fill", label: "Keep Awake", on: caffeine.isOn,
                       help: "Keep the display awake") { caffeine.toggle() }
            ToggleTile(symbol: wifi == false ? "wifi.slash" : "wifi", label: "Wi-Fi", on: wifi ?? false,
                       help: "Toggle Wi-Fi") {
                guard let current = wifi else { return }
                wifi = !current
                DispatchQueue.global(qos: .userInitiated).async { QuickSystem.setWifi(!current) }
            }
            ToggleTile(symbol: "camera.fill", label: "Mirror", on: state.showMirror, help: "Camera check") {
                withAnimation(Motion.quick) { state.showMirror.toggle() }
            }
            ToggleTile(symbol: "moon.fill", label: status.focusName ?? "Focus", on: status.focusName != nil,
                       help: status.focusName.map { "\($0) is on · Manage Focus in System Settings" }
                             ?? "Manage Focus in System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .onAppear {
            dark = QuickSystem.isDarkMode
            DispatchQueue.global(qos: .utility).async {
                let on = QuickSystem.wifiIsOn()
                DispatchQueue.main.async { wifi = on }
            }
        }
    }
}

// MARK: - Notification cards

struct NotificationGroupCard: View {
    let group: NotificationGroup
    @ObservedObject var state: IslandState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(image: group.icon, group.appName, count: group.notes.count) {
                IconButton(symbol: "xmark", size: 22, help: "Clear \(group.appName)") { state.dismissGroup(group) }
            }
            .padding(.bottom, 8)

            ForEach(Array(group.notes.enumerated()), id: \.element.id) { index, note in
                if index > 0 { HairlineDivider().padding(.vertical, 8) }
                NotificationRow(note: note,
                                onOpen: { state.open(note) },
                                onDismiss: { state.dismiss(note) })
            }
        }
        .islandCard()
    }
}

struct NotificationRow: View {
    let note: NotchNotification
    let onOpen: () -> Void
    let onDismiss: () -> Void

    private var showsSubtitle: Bool { !note.title.isEmpty && !note.subtitle.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(note.headline)
                    .font(UI.title())
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(NotificationBannerView.relative(note.date))
                    .font(UI.caption())
                    .foregroundStyle(.secondary)
            }
            if showsSubtitle {
                Text(note.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            if !note.body.isEmpty {
                Text(note.body)
                    .font(UI.body(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .contextMenu {
            Button("Open") { onOpen() }
            Button("Clear") { onDismiss() }
        }
    }
}
