import AppKit
import IslandCore
import Observation

/// Tracks connected screens and resolves which one hosts the Island. Event-driven (no polling).
@MainActor
@Observable
final class DisplayManager {
    private(set) var screens: [ScreenDescriptor] = []
    private(set) var geometry: NotchGeometry?
    var selection: DisplaySelection = .automatic { didSet { refresh() } }
    @ObservationIgnored var onChange: ((NotchGeometry?) -> Void)?
    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    func refresh() {
        let mainID = NSScreen.main.flatMap(Self.displayID)
        screens = NSScreen.screens.map { Self.describe($0, mainID: mainID) }
        let newGeometry = DisplayResolver.choose(from: screens, selection: selection).map(DisplayResolver.geometry)
        if newGeometry != geometry {
            geometry = newGeometry
            onChange?(newGeometry)
        }
    }

    func nsScreen(for descriptor: ScreenDescriptor) -> NSScreen? {
        NSScreen.screens.first { Self.displayID($0) == descriptor.id }
    }

    static func displayID(_ screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static func describe(_ s: NSScreen, mainID: UInt32?) -> ScreenDescriptor {
        let id = displayID(s) ?? 0
        return ScreenDescriptor(
            id: id,
            name: s.localizedName,
            frame: s.frame,
            visibleFrame: s.visibleFrame,
            safeAreaTop: s.safeAreaInsets.top,
            auxiliaryTopLeft: s.auxiliaryTopLeftArea,
            auxiliaryTopRight: s.auxiliaryTopRightArea,
            backingScale: s.backingScaleFactor,
            isBuiltIn: CGDisplayIsBuiltin(id) != 0,
            isMain: id == mainID
        )
    }
}
