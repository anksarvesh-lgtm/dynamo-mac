import AppKit
import IslandCore
import SwiftUI

@MainActor
enum ImageCache {
    private static let artwork = NSCache<NSString, NSImage>()
    private static let icons = NSCache<NSString, NSImage>()

    static func artwork(for media: MediaActivity) -> NSImage? {
        guard let data = media.artwork else { return nil }
        let key = (media.artworkID ?? "\(data.count)-\(data.hashValue)") as NSString
        if let img = artwork.object(forKey: key) { return img }
        guard let img = NSImage(data: data) else { return nil }
        artwork.setObject(img, forKey: key)
        return img
    }

    static func appIcon(bundleID: String) -> NSImage? {
        if let img = icons.object(forKey: bundleID as NSString) { return img }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        icons.setObject(img, forKey: bundleID as NSString)
        return img
    }
}

struct ArtworkView: View {
    var media: MediaActivity
    var size: CGFloat
    var corner: CGFloat

    var body: some View {
        ZStack {
            if let img = ImageCache.artwork(for: media) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .id(media.artworkID ?? media.trackKey)
            } else {
                LinearGradient(colors: [Color(white: 0.28), Color(white: 0.14)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note").font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .animation(.easeInOut(duration: 0.35), value: media.artworkID ?? media.trackKey)
        .accessibilityHidden(true)
    }
}

struct MediaCompactLeading: View {
    let media: MediaActivity
    var showTitle = false
    @Environment(\.islandNamespace) private var ns
    var body: some View {
        HStack(spacing: 8) {
            ArtworkView(media: media, size: 22, corner: 6)
                .islandMatched("media-artwork", in: ns)
            if showTitle {
                Text(media.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .islandMatched("media-title", in: ns)
            }
        }
    }
}

struct MediaCompactTrailing: View {
    let media: MediaActivity
    @Environment(\.islandReduceMotion) private var reduceMotion
    var body: some View {
        EqualizerView(playing: media.playbackState == .playing,
                      colors: ArtworkPalette.colors(for: media.artworkID ?? media.trackKey, image: ImageCache.artwork(for: media)),
                      reduceMotion: reduceMotion)
            .frame(width: 22, height: 16)
            .accessibilityHidden(true)
    }
}

struct MediaMinimal: View {
    let media: MediaActivity
    var body: some View {
        ArtworkView(media: media, size: 18, corner: 9)
    }
}

struct MediaExpanded: View {
    let media: MediaActivity
    @Environment(\.islandNamespace) private var ns
    @Environment(\.islandCommands) private var send

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                ArtworkView(media: media, size: 56, corner: 13)
                    .islandMatched("media-artwork", in: ns)
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(media.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .islandMatched("media-title", in: ns)
                    if !media.artist.isEmpty || !media.album.isEmpty {
                        Text([media.artist, media.album].filter { !$0.isEmpty }.joined(separator: " — "))
                            .font(.system(size: 12.5))
                            .foregroundStyle(IslandPalette.secondaryText)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let icon = ImageCache.appIcon(bundleID: media.sourceBundleID) {
                    Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                        .help(media.sourceName)
                        .accessibilityLabel("Source: \(media.sourceName)")
                }
            }
            MediaProgress(media: media) { send(.media(.seek(to: $0), sourceBundleID: media.sourceBundleID)) }
            HStack(spacing: 28) {
                IslandIconButton(symbol: "backward.fill", size: 15, label: "Previous track", enabled: media.controls.contains(.previous)) {
                    send(.media(.previous, sourceBundleID: media.sourceBundleID))
                }
                IslandIconButton(symbol: media.playbackState == .playing ? "pause.fill" : "play.fill", size: 19,
                                 label: media.playbackState == .playing ? "Pause" : "Play",
                                 enabled: media.controls.contains(.playPause)) {
                    send(.media(.togglePlayPause, sourceBundleID: media.sourceBundleID))
                }
                .contentTransition(.symbolEffect(.replace))
                IslandIconButton(symbol: "forward.fill", size: 15, label: "Next track", enabled: media.controls.contains(.next)) {
                    send(.media(.next, sourceBundleID: media.sourceBundleID))
                }
            }
        }
    }
}

/// Progress with elapsed/duration. Only ticks (once per second) while visible and playing.
struct MediaProgress: View {
    let media: MediaActivity
    var onSeek: (TimeInterval) -> Void
    @State private var dragFraction: Double?
    @Environment(\.islandContentActive) private var active

    var body: some View {
        TimelineView(.periodic(from: .now, by: clockInterval(active: active, running: media.playbackState == .playing))) { context in
            let position = media.position(at: context.date)
            let duration = media.duration
            let fraction = dragFraction ?? {
                guard let p = position, let d = duration, d > 0 else { return nil }
                return p / d
            }()
            HStack(spacing: 10) {
                Text(position.map(DurationFormatter.clock) ?? "–:––")
                    .frame(width: 42, alignment: .trailing)
                GeometryReader { geo in
                    LinearProgress(fraction: fraction ?? 0, tint: .white, height: 5)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(seekGesture(width: geo.size.width, duration: duration))
                }
                .frame(height: 14)
                Text(duration.map { "-" + DurationFormatter.clock(max(0, $0 - (position ?? 0))) } ?? "–:––")
                    .frame(width: 46, alignment: .leading)
            }
            .font(.system(size: 10.5, weight: .medium).monospacedDigit())
            .foregroundStyle(IslandPalette.secondaryText)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(DurationFormatter.spoken(position ?? 0)) of \(DurationFormatter.spoken(duration ?? 0))")
        }
    }

    private func seekGesture(width: CGFloat, duration: TimeInterval?) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                guard media.controls.contains(.seek), duration != nil, width > 0 else { return }
                dragFraction = min(1, max(0, v.location.x / width))
            }
            .onEnded { v in
                defer { dragFraction = nil }
                guard media.controls.contains(.seek), let d = duration, width > 0 else { return }
                onSeek(min(1, max(0, v.location.x / width)) * d)
            }
    }
}
