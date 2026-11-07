import AppKit
import IslandCore

/// Composition root. Wires providers → ActivityManager → Island, and UI → CommandRouter → services.
@MainActor
final class AppEnvironment {
    let settings: IslandSettings
    let bus = EventBus()
    let manager: ActivityManager
    let display = DisplayManager()
    let accessibility = AccessibilityMonitor()
    let commands = CommandRouter()
    let island: IslandViewModel
    let search = SearchViewModel()
    let window: IslandWindowController
    let timers: TimerService
    let media: MediaService
    let downloads: DownloadProvider
    let battery: BatteryProvider
    let network: NetworkProvider
    let devices: AudioDeviceProvider
    let recording: RecordingProvider
    let calendar: CalendarProvider
    let clipboard: ClipboardProvider
    let airPods: AirPodsConnectionAnimator
    private(set) var providersRunning = false
    private(set) lazy var features = FeatureHub(env: self)
    private var running: Set<String> = []

    init(settings: IslandSettings) {
        self.settings = settings
        manager = ActivityManager(bus: bus)
        island = IslandViewModel(manager: manager, settings: settings, accessibility: accessibility, commands: commands)
        window = IslandWindowController(model: island, search: search)
        let submit: (ActivityUpdate) -> Void = { [manager] in manager.submit($0) }
        timers = TimerService(bus: bus, sink: submit)
        media = MediaService(bus: bus, sink: submit)
        downloads = DownloadProvider(bus: bus, sink: submit)
        battery = BatteryProvider(bus: bus, sink: submit)
        network = NetworkProvider(bus: bus, sink: submit)
        devices = AudioDeviceProvider(bus: bus, sink: submit)
        recording = RecordingProvider(sink: submit)
        calendar = CalendarProvider(sink: submit)
        clipboard = ClipboardProvider(sink: submit)
        let router = commands
        airPods = AirPodsConnectionAnimator(sink: submit, ui: { router.perform(.ui($0)) },
                                            reduceMotion: { [weak island] in island?.reduceMotion ?? false })
        island.airPods = airPods
        devices.onAirPodsConnected = { [weak airPods] in airPods?.deviceConnected(name: $0) }
        devices.onAirPodsDisconnected = { [weak airPods] in airPods?.deviceDisconnected() }

        search.commands = commands
        search.onHeightChange = { [weak island] h in island?.searchHeight = h }

        commands.timer = { [weak self] in self?.timers.handle($0) }
        commands.media = { [weak self] c, source in self?.media.perform(c, source: source) }
        commands.download = { [weak self] in self?.downloads.handle($0) }
        commands.ui = { [weak self] in self?.handleUI($0) }

        display.selection = settings.display
        display.onChange = { [weak self] g in self?.geometryChanged(g) }
        geometryChanged(display.geometry)
        applySettings()
        observeSettings()
    }

    func start(providers: Bool = true) {
        if settings.islandEnabled { window.show() }
        providersRunning = providers
        syncProviders()
        features.start()
    }

    func showDebugPanel() { features.debug.showPanel(env: self) }

    // MARK: Providers

    /// Starts/stops each integration to match the enabled activity kinds. Each provider is independent:
    /// one failing integration never affects the others.
    private func syncProviders() {
        guard providersRunning else { return }
        let kinds = settings.enabledKinds
        toggle("media", kinds.contains(.media), start: {
            media.register(AppleMusicProvider())
            media.register(SpotifyProvider())
            media.register(VLCProvider())
        }, stop: {
            media.providers.map(\.bundleID).forEach { media.unregister(bundleID: $0) }
        })
        toggle("browserMedia", kinds.contains(.media) && settings.browserMediaEnabled, start: {
            BrowserMediaProvider.all().forEach { media.register($0) }
        }, stop: {
            BrowserMediaProvider.all().forEach { media.unregister(bundleID: $0.bundleID) }
        })
        toggle("download", kinds.contains(.download), start: { downloads.start() }, stop: { downloads.stop() })
        toggle("battery", kinds.contains(.battery), start: { battery.start() }, stop: { battery.stop() })
        toggle("network", kinds.contains(.network), start: { network.start() }, stop: { network.stop() })
        toggle("device", kinds.contains(.device), start: { devices.start() }, stop: { devices.stop() })
        toggle("recording", kinds.contains(.recording), start: { recording.start() }, stop: { recording.stop() })
        toggle("calendar", kinds.contains(.calendar), start: { calendar.start() }, stop: { calendar.stop() })
        toggle("clipboard", kinds.contains(.clipboard), start: { clipboard.start() }, stop: { clipboard.stop() })
    }

    private func toggle(_ key: String, _ on: Bool, start: () -> Void, stop: () -> Void) {
        if on, !running.contains(key) { running.insert(key); start() }
        else if !on, running.contains(key) { running.remove(key); stop() }
    }

    var runningProviders: [String] { running.sorted() }

    // MARK: Geometry / UI

    private func geometryChanged(_ g: NotchGeometry?) {
        island.updateGeometry(g)
        search.compactHeight = island.metrics.compactHeight
        window.reposition()
    }

    private func handleUI(_ c: IslandUICommand) {
        switch c {
        case .expand: island.expand()
        case .collapse: island.collapse()
        case .toggleSearch:
            guard settings.searchEnabled, settings.islandEnabled else { return }
            island.toggleSearch()
        case .presentTransient(let s): island.presentTransient(seconds: s)
        case .select(let id): manager.select(id: id)
        case .selectNext: manager.selectNext()
        case .dismiss(let id):
            if id == AirPodsConnectionAnimator.activityID { airPods.dismiss() }
            manager.dismiss(id: id)
        }
    }

    private func applySettings() {
        manager.enabledKinds = settings.enabledKinds
        island.settingsChanged()
        if display.selection != settings.display { display.selection = settings.display }
        window.reposition()
        if settings.islandEnabled { window.show() } else { window.hide() }
        syncProviders()
        if providersRunning { features.configure() }
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.enabledKinds
            _ = settings.browserMediaEnabled
            _ = settings.hoverExpansion
            _ = settings.display
            _ = settings.islandScale
            _ = settings.cornerRadius
            _ = settings.islandEnabled
            _ = settings.searchEnabled
            _ = settings.searchShortcut
            _ = settings.fileSearchEnabled
            _ = settings.webSearchEnabled
            _ = settings.webSearchProviders
            _ = settings.aiProvider
            _ = settings.aiModel
            _ = settings.performanceOverlay
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.applySettings()
                self?.observeSettings()
            }
        }
    }
}
