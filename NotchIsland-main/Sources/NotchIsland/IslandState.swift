import AppKit
import Combine
import SwiftUI

struct AppEntry: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
}

/// Notifications from one app, newest first, for the grouped shade.
struct NotificationGroup: Identifiable {
    let bundleID: String
    let appName: String
    let notes: [NotchNotification]
    var id: String { bundleID }
    var icon: NSImage { AppIconCache.icon(for: bundleID) }
}

final class IslandState: ObservableObject {
    // Inputs
    @Published var isExpanded = false { didSet { hoverChanged() } }
    @Published var isLauncherOpen = false { didSet { refreshLayout() } }
    @Published var isShadeOpen = false { didSet { refreshLayout() } }
    @Published var isDragTargeted = false { didSet { refreshLayout() } }
    @Published var query = "" { didSet { launcher.searchFiles(query) } }
    @Published private(set) var apps: [AppEntry] = []

    // Media, notifications, activities
    @Published private(set) var media: NowPlaying? { didSet { refreshLayout() } }
    @Published private(set) var banner: NotchNotification? { didSet { refreshLayout() } }
    @Published private(set) var latest: NotchNotification? { didSet { refreshLayout() } }
    @Published private(set) var recent: [NotchNotification] = []
    @Published private(set) var dismissed: Set<String> = []
    @Published private(set) var hint: IslandHint? { didSet { refreshLayout() } }
    @Published private(set) var activity: LiveActivity? { didSet { refreshLayout() } }
    @Published private(set) var stickyActivity: LiveActivity? { didSet { refreshLayout() } }
    @Published private(set) var timerActive = false { didSet { refreshLayout() } }
    @Published private(set) var indicatorsOn = false { didSet { refreshLayout() } }
    @Published var showMirror = false
    @Published var showAllClipboard = false

    /// Derived shape of the island; the view and the panel both read this.
    @Published private(set) var layout = IslandLayout()

    // Modules
    let settings = AppSettings.shared
    let mediaController = MediaController()
    let notificationWatcher = NotificationWatcher()
    let activities = ActivityCenter.shared
    let timer = TimerEngine()
    let calendar = CalendarModule()
    let clipboard = ClipboardHistory()
    let shelf = ShelfStore()
    let status = SystemStatus()
    let launcher = LauncherEngine()
    let caffeine = Caffeine.shared
    private let battery = BatteryWatcher()
    private let bluetooth = BluetoothWatcher()
    private let downloads = DownloadsWatcher()
    private let custom = CustomActivityWatcher()

    private var bannerTimer: DispatchWorkItem?
    private var hoverWork: DispatchWorkItem?
    private var notificationProblem: IslandHint?
    private var accessibilityProblem: IslandHint?
    private var cancellables = Set<AnyCancellable>()
    private var running: Set<String> = []

    static let recentLifetime: TimeInterval = 600

    init() {
        loadApps()
        bind()
        launcher.actions = quickActions()
    }

    func start() {
        applyModuleSettings()
        status.start()      // event-driven and cheap; the UI gates on the setting
        custom.start()
    }

    // MARK: - Wiring

    private func bind() {
        mediaController.$nowPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] np in
                guard let self else { return }
                self.media = self.settings.mediaEnabled ? np : nil
            }
            .store(in: &cancellables)
        mediaController.$problem
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.updateHint(mediaProblem: $0) }
            .store(in: &cancellables)
        mediaController.onVolumeChanged = { [weak self] in self?.volumeChanged($0) }

        notificationWatcher.onNotification = { [weak self] in self?.present($0) }
        notificationWatcher.onHistory = { [weak self] in self?.loadHistory($0) }
        notificationWatcher.onStatus = { [weak self] problem in
            guard let self else { return }
            self.notificationProblem = problem
            self.updateHint(mediaProblem: self.mediaController.problem)
        }

        activities.$current
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.activity = $0 }
            .store(in: &cancellables)
        activities.$sticky
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.stickyActivity = $0 }
            .store(in: &cancellables)

        timer.$total
            .receive(on: DispatchQueue.main)
            .sink { [weak self] total in self?.timerActive = total > 0 }
            .store(in: &cancellables)
        timer.onFinished = { [weak self] in
            self?.activities.show(LiveActivity(id: "timer.done", kind: .timer, symbol: "timer",
                                               title: "Timer finished", subtitle: "", progress: nil,
                                               tint: Theme.accent, duration: 8))
        }

        Publishers.CombineLatest3(status.$micInUse, status.$cameraInUse, status.$focusName)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mic, cam, focus in
                guard let self else { return }
                self.indicatorsOn = self.settings.indicatorsEnabled && (mic || cam || focus != nil)
            }
            .store(in: &cancellables)

        battery.onEvent = { [weak self] in self?.show($0, when: \.batteryAlertsEnabled) }
        bluetooth.onEvent = { [weak self] in self?.show($0, when: \.bluetoothEnabled) }
        downloads.onEvent = { [weak self] in self?.show($0, when: \.downloadsEnabled) }
        custom.onEvent = { [weak self] in self?.activities.show($0) }

        NotificationCenter.default.addObserver(forName: .notchStartTimer, object: nil, queue: .main) { [weak self] n in
            guard let self, let minutes = n.object as? Int else { return }
            self.timer.start(minutes: minutes)
            self.closeLauncher()
        }
        NotificationCenter.default.addObserver(forName: .notchModulesChanged, object: nil, queue: .main) { [weak self] _ in
            self?.applyModuleSettings()
        }
    }

    private func show(_ activity: LiveActivity, when key: KeyPath<AppSettings, Bool>) {
        guard settings[keyPath: key] else { return }
        activities.show(activity)
    }

    /// Starts/stops modules to match Settings. Safe to call repeatedly.
    func applyModuleSettings() {
        toggle("media", settings.mediaEnabled, on: { mediaController.start() },
               off: { mediaController.stop(); media = nil })
        toggle("notifications", settings.notificationsEnabled, on: { notificationWatcher.start() },
               off: { notificationWatcher.stop(); banner = nil })
        toggle("clipboard", settings.clipboardEnabled, on: { clipboard.start() }, off: { clipboard.stop() })
        toggle("downloads", settings.downloadsEnabled, on: { downloads.start() }, off: { downloads.stop() })
        // IOBluetooth triggers macOS's one-time Bluetooth permission prompt on first use; start it a
        // few seconds after launch so that dialog doesn't land on top of the island's first open.
        toggle("bluetooth", settings.bluetoothEnabled, on: {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                guard let self, self.settings.bluetoothEnabled else { return }
                self.bluetooth.start()
            }
        }, off: { bluetooth.stop() })
        toggle("battery", settings.batteryAlertsEnabled, on: { battery.start() }, off: { battery.stop() })
        toggle("calendar", settings.calendarEnabled, on: { calendar.start() }, off: { calendar.stop() })
        indicatorsOn = settings.indicatorsEnabled && (status.micInUse || status.cameraInUse || status.focusName != nil)
        refreshLayout()
    }

    private func toggle(_ name: String, _ enabled: Bool, on: () -> Void, off: () -> Void) {
        if enabled, !running.contains(name) { running.insert(name); on() }
        else if !enabled, running.contains(name) { running.remove(name); off() }
    }

    private func volumeChanged(_ value: Double) {
        guard settings.volumeHUDEnabled, !isShadeOpen else { return }
        let symbol = value <= 0.001 ? "speaker.slash.fill"
            : value < 0.34 ? "speaker.wave.1.fill"
            : value < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        activities.show(LiveActivity(id: "volume", kind: .volume, symbol: symbol, title: "Volume",
                                     subtitle: "\(Int((value * 100).rounded()))%", progress: value,
                                     tint: Theme.accent, duration: 1.6))
    }

    // MARK: - Notification list

    var visibleRecent: [NotchNotification] {
        guard settings.notificationsEnabled else { return [] }
        return recent.filter { !dismissed.contains($0.id) }.sorted { $0.date > $1.date }
    }

    var hasNotifications: Bool { !visibleRecent.isEmpty }

    var groups: [NotificationGroup] {
        var order: [String] = []
        var map: [String: [NotchNotification]] = [:]
        for note in visibleRecent {
            if map[note.bundleID] == nil { order.append(note.bundleID); map[note.bundleID] = [] }
            map[note.bundleID]?.append(note)
        }
        return order.map { NotificationGroup(bundleID: $0, appName: map[$0]!.first!.appName, notes: map[$0]!) }
    }

    var footerNotification: NotchNotification? {
        guard settings.notificationsEnabled, let latest, !dismissed.contains(latest.id),
              Date().timeIntervalSince(latest.date) < Self.recentLifetime else { return nil }
        return latest
    }

    private func loadHistory(_ history: [NotchNotification]) {
        let known = Set(recent.map(\.id))
        recent.append(contentsOf: history.filter { !known.contains($0.id) })
        trimRecent()
        refreshLayout()
    }

    // MARK: - Layout

    private func refreshLayout() {
        var l = IslandLayout()
        let ears = media != nil || timerActive || indicatorsOn || stickyActivity != nil
        l.mode = isLauncherOpen ? .launcher
               : isShadeOpen ? .shade
               : banner != nil ? .banner
               : (isExpanded || isDragTargeted) ? .expanded
               : activity != nil ? .activity
               : ears ? .compact
               : .collapsed
        l.showsMedia = media != nil
        l.compactEars = ears
        l.showsFooter = footerNotification != nil || hint != nil
        if l != layout { layout = l }
    }

    private func updateHint(mediaProblem: String?) {
        let combined = mediaProblem.map { IslandHint(text: $0) } ?? notificationProblem ?? accessibilityProblem
        if combined != hint { hint = combined }
    }

    /// Without Accessibility the hotkey is not seen while another app is frontmost, so say so.
    func setAccessibilityGranted(_ granted: Bool) {
        let problem = granted ? nil : IslandHint(
            text: "Hotkey: allow NotchIsland under Accessibility. Already on? Settings ▸ Permissions ▸ Reset.",
            settingsPane: PrivacyPane.accessibility)
        guard problem != accessibilityProblem else { return }
        accessibilityProblem = problem
        updateHint(mediaProblem: mediaController.problem)
    }

    // MARK: - Hover

    /// Hover-enter waits `hoverDelay`; hover-exit is debounced so a resize under a still pointer
    /// (AppKit briefly reports it outside) doesn't collapse the island or dismiss a banner.
    func setHovering(_ hovering: Bool) {
        hoverWork?.cancel()
        if hovering {
            guard !isExpanded else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.isExpanded else { return }
                withAnimation(Motion.spring) { self.isExpanded = true }
            }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + settings.hoverDelay, execute: work)
        } else {
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.isExpanded else { return }
                withAnimation(Motion.spring) { self.isExpanded = false }
            }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }

    private func hoverChanged() {
        if banner != nil {
            if isExpanded { bannerTimer?.cancel() } else { scheduleBannerDismiss(after: 1.5) }
        }
        refreshLayout()
    }

    // MARK: - Notifications

    private func present(_ note: NotchNotification) {
        guard settings.notificationsEnabled else { return }
        if !recent.contains(where: { $0.id == note.id }) { recent.insert(note, at: 0) }
        trimRecent()
        latest = note
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.recentLifetime + 1) { [weak self] in
            self?.refreshLayout()
        }
        guard !isShadeOpen, !isLauncherOpen else { return }
        withAnimation(Motion.spring) { banner = note }
        Feedback.tap()
        if isExpanded { bannerTimer?.cancel() } else { scheduleBannerDismiss(after: 6) }
    }

    private func trimRecent() {
        recent.sort { $0.date > $1.date }
        if recent.count > 80 { recent.removeLast(recent.count - 80) }
    }

    func dismissBanner() {
        bannerTimer?.cancel()
        withAnimation(Motion.quick) { banner = nil }
    }

    func openBanner() {
        guard let note = banner else { return }
        open(note)
    }

    func open(_ note: NotchNotification) {
        if let url = AppIconCache.url(for: note.bundleID) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config)
        }
        dismiss(note)
        dismissBanner()
    }

    func dismiss(_ note: NotchNotification) {
        withAnimation(Motion.quick) {
            _ = dismissed.insert(note.id)
            if latest?.id == note.id { latest = nil }
        }
    }

    func dismissGroup(_ group: NotificationGroup) {
        withAnimation(Motion.quick) {
            dismissed.formUnion(group.notes.map(\.id))
            if let latest, group.notes.contains(where: { $0.id == latest.id }) { self.latest = nil }
        }
    }

    func clearAll() {
        withAnimation(Motion.quick) {
            dismissed.formUnion(recent.map(\.id))
            latest = nil
        }
        Feedback.tap()
    }

    func clearLatest() { if let latest { dismiss(latest) } }

    private func scheduleBannerDismiss(after seconds: TimeInterval) {
        bannerTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismissBanner() }
        bannerTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    // MARK: - Shade

    func toggleShade() {
        if ProcessInfo.processInfo.environment["NOTCHISLAND_DEBUG"] != nil { NSLog("NotchIsland: toggleShade (was open: %d)", isShadeOpen ? 1 : 0) }
        Feedback.tap()
        withAnimation(Motion.spring) {
            if isLauncherOpen { isLauncherOpen = false; query = "" }
            isShadeOpen.toggle()
            if isShadeOpen { banner = nil }
        }
    }

    func openShade() {
        guard !isShadeOpen else { return }
        toggleShade()
    }

    func closeShade() {
        withAnimation(Motion.quick) { isShadeOpen = false }
        showMirror = false
    }

    // MARK: - Launcher

    var results: [LauncherItem] { launcher.results(for: query, apps: apps) }

    func toggleLauncher() {
        DispatchQueue.main.async {
            withAnimation(Motion.spring) {
                if self.isShadeOpen { self.isShadeOpen = false }
                self.isLauncherOpen.toggle()
            }
            if !self.isLauncherOpen { self.query = "" }
        }
    }

    func openLauncherFromShade() {
        withAnimation(Motion.spring) {
            isShadeOpen = false
            isLauncherOpen = true
        }
    }

    func closeLauncher() {
        withAnimation(Motion.quick) { isLauncherOpen = false }
        query = ""
    }

    func perform(_ item: LauncherItem) {
        switch item.kind {
        case .app(let app):
            launcher.recordLaunch(app)
            NSWorkspace.shared.openApplication(at: app.url, configuration: .init())
        case .calc(let text), .convert(let text):
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
        case .file(let url):
            NSWorkspace.shared.open(url)
        case .action(let action):
            action.run()
        }
        Feedback.tap()
        closeLauncher()
    }

    private func quickActions() -> [QuickAction] {
        [
            QuickAction(id: "lock", title: "Lock Screen", symbol: "lock.fill", keywords: ["lock"]) { QuickSystem.lockScreen() },
            QuickAction(id: "sleep", title: "Sleep", symbol: "moon.zzz.fill", keywords: ["sleep"]) { QuickSystem.sleepMac() },
            QuickAction(id: "trash", title: "Empty Trash", symbol: "trash.fill", keywords: ["trash", "empty"]) { QuickSystem.emptyTrash() },
            QuickAction(id: "dark", title: "Toggle Dark Mode", symbol: "circle.lefthalf.filled", keywords: ["dark", "light", "appearance", "theme"]) { QuickSystem.toggleDarkMode() },
            QuickAction(id: "awake", title: "Toggle Keep Awake", symbol: "cup.and.saucer.fill", keywords: ["caffeine", "awake", "amphetamine", "sleep"]) { [weak self] in self?.caffeine.toggle() },
            QuickAction(id: "wifi", title: "Toggle Wi-Fi", symbol: "wifi", keywords: ["wifi", "wireless", "network"]) {
                DispatchQueue.global(qos: .userInitiated).async {
                    if let on = QuickSystem.wifiIsOn() { QuickSystem.setWifi(!on) }
                }
            },
            QuickAction(id: "mirror", title: "Camera Mirror", symbol: "camera.fill", keywords: ["camera", "mirror", "preview", "meeting"]) { [weak self] in
                self?.showMirror = true
                self?.openShade()
            },
            QuickAction(id: "pomodoro", title: "Start 25 minute Pomodoro", symbol: "timer", keywords: ["pomodoro", "focus", "timer"]) { [weak self] in self?.timer.start(minutes: 25) },
            QuickAction(id: "settings", title: "NotchIsland Settings", symbol: "gear", keywords: ["settings", "preferences", "options"]) { SettingsWindowController.shared.show() },
        ]
    }

    // MARK: - Demo mode

    /// `NOTCHISLAND_DEMO=1`: stop the live media, notification and clipboard sources and show
    /// sample content instead, so screenshots carry no personal data. Focus, battery, camera and
    /// mic indicators stay real.
    func seedDemo() {
        mediaController.stop()
        notificationWatcher.stop()
        clipboard.stop()
        notificationProblem = nil
        hint = nil
        dismissed = []

        let now = Date()
        func note(_ id: String, _ bundle: String, _ app: String, _ title: String, _ body: String,
                  _ minutesAgo: Double) -> NotchNotification {
            NotchNotification(id: "demo.\(id)", bundleID: bundle, appName: app, title: title, subtitle: "",
                              body: body, date: now.addingTimeInterval(-minutesAgo * 60))
        }
        let notes = [
            note("m1", "com.apple.MobileSMS", "Messages", "Maya Chen", "Lunch at 1? The new ramen place just opened 🍜", 1),
            note("m2", "com.apple.MobileSMS", "Messages", "Maya Chen", "Also bring the charger you borrowed 😅", 3),
            note("c1", "com.apple.iCal", "Calendar", "Design review", "Starts in 15 minutes · Conference Room B", 9),
            note("r1", "com.apple.reminders", "Reminders", "Water the plants", "Today, 6:00 PM", 26),
            note("e1", "com.apple.mail", "Mail", "App Store Connect", "Your build 1.0.0 (42) has completed processing.", 41),
        ]
        recent = notes
        latest = notes[0]

        calendar.seed(CalendarModule.NextEvent(
            title: "Design review", start: now.addingTimeInterval(15 * 60), end: now.addingTimeInterval(60 * 60),
            location: "Conference Room B", joinURL: URL(string: "https://meet.google.com/abc-defg-hij"), color: UI.info))
        clipboard.seed(["https://github.com/Edwardrem/NotchIsland", "swift build -c release",
                        "Ship v1.0 on Friday, demo at 3 pm"])
        timer.start(minutes: 25, alreadyElapsed: 7 * 60 + 18)

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("NotchIslandDemo", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let files = ["Q4 Roadmap.pdf", "Hero shot.png", "Launch notes.md"].map { tmp.appendingPathComponent($0) }
        for f in files where !FileManager.default.fileExists(atPath: f.path) {
            FileManager.default.createFile(atPath: f.path, contents: Data())
        }
        shelf.add(files)

        // The media controller's last value lands on the main queue after stop(); seed after it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            self.media = NowPlaying(player: .music, title: "Midnight City", artist: "M83",
                                    album: "Hurry Up, We're Dreaming", isPlaying: true, elapsed: 73, duration: 244,
                                    trackID: "demo", artworkHint: "", artwork: Self.demoArtwork(), sampledAt: Date())
        }
    }

    func demoBanner() {
        guard let note = recent.first else { return }
        withAnimation(Motion.spring) { banner = note }
    }

    func demoActivity() {
        activities.show(LiveActivity(id: "demo.airpods", kind: .bluetooth, symbol: "airpodspro", title: "AirPods Pro",
                                     subtitle: "L 84% · R 82% · Case 61%", progress: nil, tint: UI.info, duration: 30))
    }

    private static func demoArtwork() -> NSImage {
        NSImage(size: NSSize(width: 300, height: 300), flipped: false) { rect in
            NSGradient(colorsAndLocations:
                (NSColor(calibratedRed: 0.98, green: 0.45, blue: 0.40, alpha: 1), 0),
                (NSColor(calibratedRed: 0.62, green: 0.30, blue: 0.95, alpha: 1), 0.6),
                (NSColor(calibratedRed: 0.15, green: 0.20, blue: 0.55, alpha: 1), 1))!
                .draw(in: rect, angle: -55)
            NSColor.white.withAlphaComponent(0.18).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 70, dy: 70)).fill()
            NSColor.white.withAlphaComponent(0.92).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 118, dy: 118)).fill()
            NSColor(calibratedRed: 0.62, green: 0.30, blue: 0.95, alpha: 1).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 138, dy: 138)).fill()
            return true
        }
    }

    private func loadApps() {
        let dirs = ["/Applications", "/Applications/Utilities", "/System/Applications",
                    "/System/Applications/Utilities",
                    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
        var found: [URL: AppEntry] = [:]
        for dir in dirs {
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]) else { continue }
            for url in items where url.pathExtension == "app" {
                found[url] = AppEntry(url: url)
            }
        }
        apps = found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
