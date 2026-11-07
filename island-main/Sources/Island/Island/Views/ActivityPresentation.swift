import IslandCore
import SwiftUI

/// Maps an activity to its compact / minimal / expanded representation. Adding a new activity type
/// means adding a case here and a view file under Activities/ — the Island itself doesn't change.
enum ActivityPresentation {
    static func compactStyle(for a: Activity?, showsTitle: Bool = false) -> CompactStyle {
        guard let a else { return .standard }
        switch a.content {
        case .media: return showsTitle ? .wide : .standard
        case .device(let d): return d.airPods != nil ? .standard : .wide
        case .calendar, .clipboard, .event, .network: return .wide
        default: return .standard
        }
    }

    static func expandedStyle(for a: Activity?) -> ExpandedStyle {
        guard let a else { return .home }
        switch a.content {
        case .media: return .media
        case .timer: return .timer
        case .download: return .download
        case .device: return .device
        case .recording, .battery, .network, .calendar, .clipboard, .event: return .event
        }
    }

    static func accessibilityLabel(for a: Activity) -> String {
        switch a.content {
        case .media(let m): "\(m.playbackState == .playing ? "Playing" : "Paused"): \(m.title)\(m.artist.isEmpty ? "" : " by \(m.artist)"), \(m.sourceName)"
        case .timer(let t): (t.label.isEmpty || t.label == "Timer" ? "Timer" : "Timer \(t.label)") + ", \(DurationFormatter.spoken(t.remaining(at: Date()))) remaining"
        case .download(let d): "Downloading \(d.filename)\(d.fraction.map { ", \(Int($0 * 100)) percent" } ?? "")"
        case .recording(let r): r.camera ? "Camera in use" : "Microphone in use" + (r.microphone && r.camera ? " and microphone" : "")
        case .battery(let b): "Battery \(b.level) percent\(b.isCharging ? ", charging" : "")"
        case .network(let n): n.connected ? "Network connected" : "Network offline"
        case .device(let d): "\(d.name) \(d.connected ? "connected" : "disconnected")"
        case .calendar(let c): "Calendar: \(c.title)"
        case .clipboard(let c): "Copied \(c.preview)"
        case .event(let e): [e.title, e.subtitle].compactMap { $0 }.joined(separator: ", ")
        }
    }
}

struct CompactLeadingView: View {
    let activity: Activity
    var showsTitle = false
    var body: some View {
        switch activity.content {
        case .media(let m): MediaCompactLeading(media: m, showTitle: showsTitle)
        case .timer(let t): TimerCompactLeading(timer: t, id: activity.id)
        case .download(let d): DownloadCompactLeading(download: d, id: activity.id)
        case .recording(let r): RecordingCompactLeading(recording: r, id: activity.id)
        case .battery(let b): BatteryCompactLeading(battery: b, id: activity.id)
        case .network(let n): SimpleCompactLeading(symbol: NetworkPresentation.symbol(n), tint: IslandPalette.network, text: NetworkPresentation.title(n), id: activity.id)
        case .device(let d): DeviceCompactLeading(device: d, id: activity.id)
        case .calendar(let c): SimpleCompactLeading(symbol: "calendar", tint: IslandPalette.hex(c.calendarColorHex) ?? .red, text: c.title, id: activity.id)
        case .clipboard(let c): SimpleCompactLeading(symbol: "doc.on.clipboard", tint: .white, text: c.preview, id: activity.id)
        case .event(let e): SimpleCompactLeading(symbol: e.symbol, tint: IslandPalette.hex(e.tintHex) ?? .white, text: e.title, id: activity.id)
        }
    }
}

struct CompactTrailingView: View {
    let activity: Activity
    var body: some View {
        switch activity.content {
        case .media(let m): MediaCompactTrailing(media: m)
        case .timer(let t): TimerCompactTrailing(timer: t)
        case .download(let d): DownloadCompactTrailing(download: d)
        case .recording(let r): RecordingCompactTrailing(recording: r)
        case .battery(let b): BatteryCompactTrailing(battery: b)
        case .network(let n): CompactTrailingText(text: n.connected ? "On" : "Off", tint: IslandPalette.network)
        case .device(let d): DeviceCompactTrailing(device: d)
        case .calendar(let c): CalendarCompactTrailing(event: c)
        case .clipboard: CompactTrailingText(text: "Copied", tint: IslandPalette.secondaryText)
        case .event(let e): CompactTrailingText(text: e.subtitle ?? "", tint: IslandPalette.secondaryText)
        }
    }
}

/// Tiny circular indicator for secondary activities (iPhone "minimal" presentation).
struct MinimalView: View {
    let activity: Activity
    var body: some View {
        switch activity.content {
        case .media(let m): MediaMinimal(media: m)
        case .timer(let t): TimerMinimal(timer: t)
        case .download(let d):
            ZStack {
                ProgressRing(fraction: d.fraction ?? 0, tint: IslandPalette.download, lineWidth: 2)
                Image(systemName: "arrow.down").font(.system(size: 9, weight: .bold)).foregroundStyle(IslandPalette.download)
            }.padding(5)
        case .recording(let r): Image(systemName: r.camera ? "video.fill" : "mic.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(IslandPalette.recording)
        case .battery(let b): Image(systemName: BatteryPresentation.symbol(b)).font(.system(size: 11, weight: .bold)).foregroundStyle(BatteryPresentation.tint(b))
        case .network(let n): Image(systemName: NetworkPresentation.symbol(n)).font(.system(size: 11, weight: .bold)).foregroundStyle(IslandPalette.network)
        case .device(let d): Image(systemName: DevicePresentation.symbol(d)).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
        case .calendar(let c): Image(systemName: "calendar").font(.system(size: 11, weight: .bold)).foregroundStyle(IslandPalette.hex(c.calendarColorHex) ?? .red)
        case .clipboard: Image(systemName: "doc.on.clipboard").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
        case .event(let e): Image(systemName: e.symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(IslandPalette.hex(e.tintHex) ?? .white)
        }
    }
}

struct ExpandedActivityView: View {
    let activity: Activity
    var body: some View {
        switch activity.content {
        case .media(let m): MediaExpanded(media: m)
        case .timer(let t): TimerExpanded(timer: t, id: activity.id)
        case .download(let d): DownloadExpanded(download: d, id: activity.id)
        case .recording(let r): RecordingExpanded(recording: r, id: activity.id)
        case .battery(let b): BatteryExpanded(battery: b, id: activity.id)
        case .network(let n): EventLikeExpanded(symbol: NetworkPresentation.symbol(n), tint: IslandPalette.network, title: NetworkPresentation.title(n), subtitle: NetworkPresentation.subtitle(n), id: activity.id)
        case .device(let d):
            if d.airPods != nil { AirPodsConnectionView(device: d, id: activity.id) } else { HeadphonesConnectedView(device: d, id: activity.id) }
        case .calendar(let c): CalendarExpanded(event: c, id: activity.id)
        case .clipboard(let c): EventLikeExpanded(symbol: "doc.on.clipboard", tint: .white, title: "Copied to clipboard", subtitle: c.preview, id: activity.id)
        case .event(let e): EventLikeExpanded(symbol: e.symbol, tint: IslandPalette.hex(e.tintHex) ?? .white, title: e.title, subtitle: e.subtitle, id: activity.id)
        }
    }
}

// MARK: Generic pieces

struct SimpleCompactLeading: View {
    var symbol: String
    var tint: Color
    var text: String
    var id: String
    @Environment(\.islandNamespace) private var ns
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .islandMatched("icon-\(id)", in: ns)
            Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
        }
    }
}

struct CompactTrailingText: View {
    var text: String
    var tint: Color
    var body: some View {
        Text(text).font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(tint).lineLimit(1)
    }
}

struct EventLikeExpanded: View {
    var symbol: String
    var tint: Color
    var title: String
    var subtitle: String?
    var id: String
    @Environment(\.islandNamespace) private var ns
    @Environment(\.islandCommands) private var send
    var body: some View {
        HStack(alignment: .center) {
            EventExpandedView(symbol: symbol, tint: tint, title: title, subtitle: subtitle, ns: ns, matchID: "icon-\(id)")
            IslandIconButton(symbol: "xmark", size: 11, label: "Dismiss") { send(.ui(.dismiss(activityID: id))) }
        }
    }
}
