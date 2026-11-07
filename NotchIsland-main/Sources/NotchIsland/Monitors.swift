import AppKit
import AVFoundation
import Combine
import CoreAudio
import IOBluetooth
import IOKit.ps
import SwiftUI

// MARK: - Battery (charger plugged in / unplugged, low battery)

final class BatteryWatcher {
    var onEvent: ((LiveActivity) -> Void)?
    private var source: CFRunLoopSource?
    private var last: Battery.Info?
    private var warned: Set<Int> = []
    private static weak var instance: BatteryWatcher?

    func start() {
        Self.instance = self
        last = Battery.read()
        let callback: IOPowerSourceCallbackType = { _ in BatteryWatcher.instance?.changed() }
        if let src = IOPSNotificationCreateRunLoopSource(callback, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
            source = src
        }
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
        source = nil
    }

    private func changed() {
        let now = Battery.read()
        defer { last = now }
        guard let was = last else { return }
        if was.onAC != now.onAC {
            onEvent?(LiveActivity(
                id: "battery.power", kind: .battery,
                symbol: now.onAC ? "bolt.fill" : "battery.75percent",
                title: now.onAC ? (now.percent >= 100 ? "Charged" : "Charging") : "On Battery",
                subtitle: "\(now.percent)%", progress: Double(now.percent) / 100,
                tint: now.onAC ? UI.success : .white, duration: 3.5))
        }
        if !now.onAC {
            for level in [20, 10, 5] where now.percent <= level && was.percent > level && !warned.contains(level) {
                warned.insert(level)
                onEvent?(LiveActivity(
                    id: "battery.low", kind: .battery, symbol: "battery.25percent",
                    title: "Low Battery", subtitle: "\(now.percent)% remaining",
                    progress: Double(now.percent) / 100, tint: UI.danger, duration: 7))
                Feedback.alert()
            }
        } else {
            warned.removeAll()
        }
    }
}

// MARK: - Mic / camera / Focus status

final class SystemStatus: ObservableObject {
    @Published private(set) var micInUse = false
    @Published private(set) var cameraInUse = false
    @Published private(set) var focusName: String?

    private var cameraObservation: NSKeyValueObservation?
    private var micDevice: AudioObjectID = 0
    private var focusTimer: Timer?
    private var started = false

    private static let focusURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")

    func start() {
        guard !started else { return }
        started = true
        startMic()
        startCamera()
        readFocus()
        focusTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.readFocus() }
    }

    // Microphone: CoreAudio tells us when the default input device is running "somewhere".
    private func startMic() {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { [weak self] _, _ in
            self?.bindMicDevice()
        }
        bindMicDevice()
    }

    private func bindMicDevice() {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var dev = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr,
              dev != 0, dev != micDevice else { return }
        micDevice = dev
        var running = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(dev, &running, .main) { [weak self] _, _ in self?.readMic() }
        readMic()
    }

    private func readMic() {
        guard micDevice != 0 else { return }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(micDevice, &addr, 0, nil, &size, &value) == noErr else { return }
        let inUse = value != 0
        if inUse != micInUse { micInUse = inUse }
    }

    // Camera: AVFoundation exposes whether another app has the camera open.
    private func startCamera() {
        guard let device = AVCaptureDevice.default(for: .video) else { return }
        cameraObservation = device.observe(\.isInUseByAnotherApplication, options: [.initial, .new]) { [weak self] dev, _ in
            DispatchQueue.main.async {
                if self?.cameraInUse != dev.isInUseByAnotherApplication { self?.cameraInUse = dev.isInUseByAnotherApplication }
            }
        }
    }

    // Focus: the active assertion lives in a JSON file under ~/Library/DoNotDisturb.
    private func readFocus() {
        var name: String?
        if let data = try? Data(contentsOf: Self.focusURL),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let entries = json["data"] as? [[String: Any]] {
            for entry in entries {
                guard let records = entry["storeAssertionRecords"] as? [[String: Any]], let first = records.first else { continue }
                let details = first["assertionDetails"] as? [String: Any]
                let identifier = details?["assertionDetailsModeIdentifier"] as? String ?? "com.apple.donotdisturb.mode.default"
                name = Self.focusDisplayName(identifier)
                break
            }
        }
        if name != focusName { focusName = name }
    }

    private static func focusDisplayName(_ identifier: String) -> String {
        let tail = identifier.components(separatedBy: ".").last ?? identifier
        switch tail.lowercased() {
        case "default": return "Do Not Disturb"
        case "sleep": return "Sleep"
        case "work": return "Work"
        case "personal": return "Personal"
        case "driving": return "Driving"
        case "fitness": return "Fitness"
        case "gaming": return "Gaming"
        case "mindfulness": return "Mindfulness"
        case "reading": return "Reading"
        default: return tail.prefix(1).uppercased() + tail.dropFirst()
        }
    }
}

// MARK: - Bluetooth (AirPods etc. connect, with per-bud battery)

final class BluetoothWatcher: NSObject {
    var onEvent: ((LiveActivity) -> Void)?
    private var connectNote: IOBluetoothUserNotification?

    func start() {
        connectNote = IOBluetoothDevice.register(forConnectNotifications: self,
                                                 selector: #selector(deviceConnected(_:device:)))
    }

    func stop() {
        connectNote?.unregister()
        connectNote = nil
    }

    @objc private func deviceConnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let name = device.name ?? "Bluetooth device"
        let key = device.addressString ?? name
        device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
        // Battery registry entries appear a moment after the link comes up.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { [weak self] in
            let battery = Self.batterySummary(for: name)
            let activity = LiveActivity(
                id: "bt.\(key)", kind: .bluetooth, symbol: Self.symbol(for: name),
                title: name, subtitle: battery ?? "Connected", progress: nil, tint: UI.info, duration: 5)
            DispatchQueue.main.async {
                self?.onEvent?(activity)
                Feedback.tap()
            }
        }
    }

    @objc private func deviceDisconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        note.unregister()
        let name = device.name ?? "Bluetooth device"
        onEvent?(LiveActivity(id: "bt.off.\(device.addressString ?? name)", kind: .bluetooth,
                              symbol: Self.symbol(for: name), title: name, subtitle: "Disconnected",
                              progress: nil, tint: UI.muted, duration: 3))
    }

    /// Reads BatteryPercentLeft/Right/Case (AirPods) or BatteryPercent (others) from the IO registry.
    static func batterySummary(for name: String) -> String? {
        for key in ["BatteryPercentLeft", "BatteryPercent"] {
            let xml = QuickSystem.run("/usr/sbin/ioreg", ["-r", "-k", key, "-a", "-l"])
            guard let data = xml.data(using: .utf8),
                  let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [Any]
            else { continue }
            var found: [String: Any]?
            func walk(_ node: Any) {
                guard found == nil else { return }
                if let dict = node as? [String: Any] {
                    if dict[key] != nil {
                        let product = (dict["Product"] as? String) ?? (dict["BluetoothName"] as? String) ?? ""
                        if product.isEmpty || name.isEmpty || product.localizedCaseInsensitiveContains(name)
                            || name.localizedCaseInsensitiveContains(product) {
                            found = dict
                            return
                        }
                    }
                    dict.values.forEach(walk)
                } else if let arr = node as? [Any] {
                    arr.forEach(walk)
                }
            }
            plist.forEach(walk)
            guard let d = found else { continue }
            if let l = d["BatteryPercentLeft"] as? Int, let r = d["BatteryPercentRight"] as? Int {
                var parts = ["L \(l)%", "R \(r)%"]
                if let c = d["BatteryPercentCase"] as? Int, c > 0 { parts.append("Case \(c)%") }
                return parts.joined(separator: " · ")
            }
            if let p = d["BatteryPercent"] as? Int { return "\(p)%" }
        }
        return nil
    }

    static func symbol(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("beats") { return "beats.headphones" }
        if n.contains("keyboard") { return "keyboard" }
        if n.contains("mouse") { return "magicmouse" }
        if n.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
        if n.contains("headphone") || n.contains("buds") { return "headphones" }
        return "dot.radiowaves.left.and.right"
    }
}

// MARK: - Downloads (Safari / Chrome / Finder partial files in ~/Downloads)

final class DownloadsWatcher {
    var onEvent: ((LiveActivity) -> Void)?
    private var source: DispatchSourceFileSystemObject?
    private var timer: Timer?
    private var active: Set<String> = []
    private let directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    private static let partialExtensions: Set<String> = ["crdownload", "download", "part", "partial"]

    func start() {
        let fd = Darwin.open(directory.path, O_EVTONLY)
        if fd >= 0 {
            let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write], queue: .main)
            src.setEventHandler { [weak self] in self?.scan() }
            src.setCancelHandler { Darwin.close(fd) }
            src.resume()
            source = src
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, !self.active.isEmpty else { return }
            self.scan()
        }
        scan()
    }

    func stop() {
        source?.cancel(); source = nil
        timer?.invalidate(); timer = nil
    }

    private func scan() {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles])
        else { return }
        // Only partials still being written to count; abandoned ".crdownload" leftovers from days
        // ago must not sit in the island as "Downloading…" forever.
        let partials = items.filter {
            Self.partialExtensions.contains($0.pathExtension.lowercased()) &&
            Date().timeIntervalSince(Self.lastModified($0)) < 120
        }

        for url in partials {
            let key = url.path
            let name = url.deletingPathExtension().lastPathComponent
            var progress: Double?
            var subtitle = "Downloading…"
            if url.pathExtension.lowercased() == "download",
               let data = try? Data(contentsOf: url.appendingPathComponent("Info.plist")),
               let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
               let total = (plist["DownloadEntryProgressTotalToLoad"] as? NSNumber)?.doubleValue, total > 0,
               let soFar = (plist["DownloadEntryProgressBytesSoFar"] as? NSNumber)?.doubleValue {
                progress = min(1, soFar / total)
                subtitle = "\(Int((progress ?? 0) * 100))% · \(ByteCountFormatter.string(fromByteCount: Int64(soFar), countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file))"
            } else {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if size > 0 { subtitle = "Downloading… \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))" }
            }
            active.insert(key)
            onEvent?(LiveActivity(id: "dl.\(key)", kind: .download, symbol: "arrow.down.circle",
                                  title: name, subtitle: subtitle, progress: progress, tint: UI.info, duration: 0))
        }

        let stillThere = Set(partials.map(\.path))
        for key in active.subtracting(stillThere) {
            active.remove(key)
            let base = URL(fileURLWithPath: key).deletingPathExtension().lastPathComponent
            ActivityCenter.shared.dismiss(id: "dl.\(key)")
            // Announce completion only when the finished file actually appeared (a partial that
            // merely went stale or was cancelled just disappears quietly).
            guard let finished = items.first(where: { $0.lastPathComponent == base }) else { continue }
            onEvent?(LiveActivity(id: "dl.done.\(key)", kind: .download, symbol: "checkmark.circle.fill",
                                  title: base, subtitle: "Download complete", progress: nil, tint: UI.success,
                                  image: NSWorkspace.shared.icon(forFile: finished.path), duration: 4))
            Feedback.tap()
        }
    }

    /// Modification time; for Safari's `.download` package, the newest file inside it.
    private static func lastModified(_ url: URL) -> Date {
        let own = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
              let inner = try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
        else { return own }
        return inner.compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            .max().map { max($0, own) } ?? own
    }
}

// MARK: - Clipboard history

final class ClipboardHistory: ObservableObject {
    struct Item: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let date: Date
    }

    @Published private(set) var items: [Item] = []
    private var timer: Timer?
    private var lastCount = NSPasteboard.general.changeCount
    private var ignoreNext = false

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in self?.poll() }
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastCount else { return }
        lastCount = pb.changeCount
        if ignoreNext { ignoreNext = false; return }
        // Password managers mark secrets as concealed/transient; never keep those.
        if let types = pb.types, types.contains(where: {
            $0.rawValue.contains("ConcealedType") || $0.rawValue.contains("TransientType") }) { return }
        guard let text = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, text.count <= 4000 else { return }
        items.removeAll { $0.text == text }
        items.insert(Item(text: text, date: Date()), at: 0)
        if items.count > 25 { items.removeLast(items.count - 25) }
    }

    /// Demo mode: replace the history with sample text and stop watching the pasteboard.
    func seed(_ texts: [String]) {
        stop()
        items = texts.enumerated().map { Item(text: $0.element, date: Date().addingTimeInterval(-Double($0.offset + 1) * 240)) }
    }

    func copy(_ item: Item) {
        ignoreNext = true
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(item.text, forType: .string)
        lastCount = pb.changeCount
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
        Feedback.tap()
    }

    func remove(_ item: Item) { items.removeAll { $0.id == item.id } }
    func clear() { items.removeAll() }
}

// MARK: - Custom activities (Shortcuts / scripts)

/// Anything can push a live activity by writing JSON to
/// `~/Library/Application Support/NotchIsland/activity.json`, e.g. from a Shortcuts "Run Shell Script":
///   echo '{"title":"Build done","subtitle":"main · 42s","symbol":"hammer.fill","seconds":5}' > ".../activity.json"
/// Keys: title, subtitle, symbol (SF Symbol), progress (0–1), seconds (auto-dismiss), tint (hex).
final class CustomActivityWatcher {
    var onEvent: ((LiveActivity) -> Void)?
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/NotchIsland")
    static let fileURL = directory.appendingPathComponent("activity.json")
    private var timer: Timer?
    private var lastModified: Date?

    func start() {
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        lastModified = modified()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.check() }
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func modified() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: Self.fileURL.path))?[.modificationDate] as? Date
    }

    private func check() {
        let m = modified()
        guard m != lastModified else { return }
        lastModified = m
        guard let m, let data = try? Data(contentsOf: Self.fileURL),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let title = json["title"] as? String, !title.isEmpty else { return }
        let tint = (json["tint"] as? String).flatMap { Color(hex: $0) } ?? Theme.accent
        onEvent?(LiveActivity(
            id: "custom.\(m.timeIntervalSince1970)", kind: .custom,
            symbol: json["symbol"] as? String ?? "sparkles",
            title: title, subtitle: json["subtitle"] as? String ?? "",
            progress: (json["progress"] as? NSNumber)?.doubleValue,
            tint: tint, duration: (json["seconds"] as? NSNumber)?.doubleValue ?? 5))
    }
}

// MARK: - Visibility (hide over full-screen apps / specific apps)

final class VisibilityMonitor {
    var onChange: ((Bool) -> Void)?
    private var timer: Timer?
    private var last: Bool?
    private var observer: Any?

    func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.evaluate() }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.evaluate() }
        evaluate()
    }

    func evaluate() {
        let settings = AppSettings.shared
        var visible = true
        if let app = NSWorkspace.shared.frontmostApplication, app != NSRunningApplication.current {
            if let bundleID = app.bundleIdentifier, settings.hiddenAppIDs.contains(bundleID) {
                visible = false
            } else if settings.hideInFullscreen, Self.isFullscreen(pid: app.processIdentifier) {
                visible = false
            }
        }
        if visible != last {
            last = visible
            onChange?(visible)
        }
    }

    /// True when the app owns a normal-layer window covering the notched screen.
    static func isFullscreen(pid: pid_t) -> Bool {
        let screen = NotchGeometry.current.screen.frame
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return false }
        for window in list {
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { continue }
            if abs(rect.width - screen.width) < 2, abs(rect.height - screen.height) < 2 { return true }
        }
        return false
    }
}
