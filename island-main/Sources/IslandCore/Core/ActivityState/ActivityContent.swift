import Foundation

public enum ActivityContent: Equatable, Sendable {
    case media(MediaActivity)
    case timer(TimerActivity)
    case download(DownloadActivity)
    case recording(RecordingActivity)
    case battery(BatteryActivity)
    case network(NetworkActivity)
    case device(DeviceActivity)
    case calendar(CalendarActivity)
    case clipboard(ClipboardActivity)
    case event(SystemEventActivity)
}

// MARK: - Media

public enum PlaybackState: String, Equatable, Sendable, Codable { case playing, paused, stopped }

public enum MediaControl: String, Hashable, Sendable, CaseIterable { case playPause, next, previous, seek }

public struct MediaActivity: Equatable, Sendable {
    public var sourceBundleID: String
    public var sourceName: String
    public var title: String
    public var artist: String
    public var album: String
    /// Raw image bytes. Equality is cheap because `artworkID` changes whenever the artwork does.
    public var artwork: Data?
    public var artworkID: String?
    public var playbackState: PlaybackState
    /// Elapsed position captured at `positionTimestamp`. Extrapolate while playing.
    public var elapsed: TimeInterval?
    public var positionTimestamp: Date
    public var duration: TimeInterval?
    public var controls: Set<MediaControl>

    public init(sourceBundleID: String, sourceName: String, title: String, artist: String = "", album: String = "",
                artwork: Data? = nil, artworkID: String? = nil, playbackState: PlaybackState,
                elapsed: TimeInterval? = nil, positionTimestamp: Date = Date(), duration: TimeInterval? = nil,
                controls: Set<MediaControl> = []) {
        self.sourceBundleID = sourceBundleID
        self.sourceName = sourceName
        self.title = title
        self.artist = artist
        self.album = album
        self.artwork = artwork
        self.artworkID = artworkID
        self.playbackState = playbackState
        self.elapsed = elapsed
        self.positionTimestamp = positionTimestamp
        self.duration = duration
        self.controls = controls
    }

    public static func == (a: Self, b: Self) -> Bool {
        a.sourceBundleID == b.sourceBundleID && a.title == b.title && a.artist == b.artist && a.album == b.album
            && a.artworkID == b.artworkID && (a.artworkID != nil || a.artwork == b.artwork)
            && a.playbackState == b.playbackState && a.elapsed == b.elapsed
            && a.positionTimestamp == b.positionTimestamp && a.duration == b.duration && a.controls == b.controls
    }

    /// Track identity used for artwork/title transitions.
    public var trackKey: String { "\(sourceBundleID)|\(title)|\(artist)|\(album)" }

    public func position(at date: Date) -> TimeInterval? {
        guard let elapsed else { return nil }
        var p = elapsed
        if playbackState == .playing { p += max(0, date.timeIntervalSince(positionTimestamp)) }
        if let duration, duration > 0 { p = min(p, duration) }
        return max(0, p)
    }
}

// MARK: - Timer

public struct TimerActivity: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case running(endDate: Date)
        case paused(remaining: TimeInterval)
        case finished(at: Date)
    }
    public var timerID: UUID
    public var label: String
    public var duration: TimeInterval
    public var state: State

    public init(timerID: UUID = UUID(), label: String, duration: TimeInterval, state: State) {
        self.timerID = timerID
        self.label = label
        self.duration = duration
        self.state = state
    }

    public func remaining(at date: Date) -> TimeInterval {
        switch state {
        case .running(let end): max(0, end.timeIntervalSince(date))
        case .paused(let r): max(0, r)
        case .finished: 0
        }
    }

    public func fraction(at date: Date) -> Double {
        guard duration > 0 else { return 1 }
        return min(1, max(0, 1 - remaining(at: date) / duration))
    }
}

// MARK: - Download

public struct DownloadActivity: Equatable, Sendable {
    public enum State: String, Equatable, Sendable { case active, completed, failed, cancelled }
    public var filename: String
    public var fileURL: URL?
    /// 0...1 when known.
    public var fraction: Double?
    public var completedBytes: Int64
    public var totalBytes: Int64?
    public var bytesPerSecond: Double?
    public var estimatedTimeRemaining: TimeInterval?
    public var state: State
    public var isCancellable: Bool
    public var isPausable: Bool
    public var isPaused: Bool

    public init(filename: String, fileURL: URL? = nil, fraction: Double? = nil, completedBytes: Int64 = 0, totalBytes: Int64? = nil,
                bytesPerSecond: Double? = nil, estimatedTimeRemaining: TimeInterval? = nil, state: State = .active,
                isCancellable: Bool = false, isPausable: Bool = false, isPaused: Bool = false) {
        self.filename = filename
        self.fileURL = fileURL
        self.fraction = fraction
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.bytesPerSecond = bytesPerSecond
        self.estimatedTimeRemaining = estimatedTimeRemaining
        self.state = state
        self.isCancellable = isCancellable
        self.isPausable = isPausable
        self.isPaused = isPaused
    }
}

// MARK: - Recording (microphone / camera in use)

public struct RecordingActivity: Equatable, Sendable {
    public var microphone: Bool
    public var camera: Bool
    public var startedAt: Date
    public init(microphone: Bool, camera: Bool, startedAt: Date) {
        self.microphone = microphone
        self.camera = camera
        self.startedAt = startedAt
    }
}

// MARK: - Battery

public struct BatteryActivity: Equatable, Sendable {
    public enum Reason: String, Equatable, Sendable { case pluggedIn, unplugged, low, full }
    public var level: Int
    public var isCharging: Bool
    public var reason: Reason
    public init(level: Int, isCharging: Bool, reason: Reason) {
        self.level = level
        self.isCharging = isCharging
        self.reason = reason
    }
}

// MARK: - Network

public struct NetworkActivity: Equatable, Sendable {
    public enum Interface: String, Equatable, Sendable { case wifi, ethernet, cellular, other, none }
    public var connected: Bool
    public var interface: Interface
    public init(connected: Bool, interface: Interface) {
        self.connected = connected
        self.interface = interface
    }
}

// MARK: - Device

public struct DeviceActivity: Equatable, Sendable {
    public enum DeviceType: String, Equatable, Sendable { case headphones, speaker, bluetooth, display, other }
    public var name: String
    public var type: DeviceType
    public var connected: Bool
    /// Resolved AirPods model, when the device is AirPods.
    public var airPods: AirPodsModel?
    /// Bluetooth product ID (Apple vendor), used to look up model-specific artwork.
    public var productID: Int?
    /// Battery levels when the system reports them.
    public var battery: AirPodsBattery?

    public init(name: String, type: DeviceType, connected: Bool, airPods: AirPodsModel? = nil,
                productID: Int? = nil, battery: AirPodsBattery? = nil) {
        self.name = name
        self.type = type
        self.connected = connected
        self.airPods = airPods
        self.productID = productID
        self.battery = battery
    }
}

// MARK: - Calendar

public struct CalendarActivity: Equatable, Sendable {
    public var title: String
    public var start: Date
    public var end: Date
    public var location: String?
    public var calendarColorHex: String?
    public init(title: String, start: Date, end: Date, location: String? = nil, calendarColorHex: String? = nil) {
        self.title = title
        self.start = start
        self.end = end
        self.location = location
        self.calendarColorHex = calendarColorHex
    }
}

// MARK: - Clipboard

public struct ClipboardActivity: Equatable, Sendable {
    public var preview: String
    public var typeDescription: String
    public init(preview: String, typeDescription: String) {
        self.preview = preview
        self.typeDescription = typeDescription
    }
}

// MARK: - Generic short-lived system event

public struct SystemEventActivity: Equatable, Sendable {
    /// SF Symbol name.
    public var symbol: String
    public var title: String
    public var subtitle: String?
    public var tintHex: String?
    public init(symbol: String, title: String, subtitle: String? = nil, tintHex: String? = nil) {
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.tintHex = tintHex
    }
}
